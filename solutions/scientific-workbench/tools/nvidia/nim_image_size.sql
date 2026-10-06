-- =============================================================================
-- tools/nvidia/nim_image_size.sql
-- UDF: Probe OCI manifest from nvcr.io — returns compressed size, digest, layers
-- =============================================================================
-- PURPOSE:
--   1. Pre-flight check before mirroring: validates entitlement, predicts digest
--   2. Size check: ensures image + weights fit within 93.13 GiB node storage cap
--   3. Entitlement check via HTTP status:
--      - 200: accessible, key valid, license accepted
--      - 401: bad NGC API key
--      - 403: no entitlement or unaccepted click-through license
--      - 404: wrong repo/tag
--
-- ARCHITECTURE:
--   Runs as a UDF (not a container job) because Snowflake SECRET_STRING cannot
--   be read back through SQL. The measurement happens where the key lives.
--   No compute pool needed, no container needed.
--
-- USAGE:
--   SELECT SCIENTIFIC_WORKBENCH.CATALOG.NIM_IMAGE_SIZE('nim/mit/boltz2', '1.8.0');
--   Returns: {'compressed_gib': 9.93, 'layers': 109, 'digest': 'sha256:f9da...', 'status': 200}
--
-- NOTES:
--   - Resolves linux/amd64 from multi-arch manifest index (aarch64 exists for GB200)
--   - Uses NGC_REGISTRY_PULL_EAI (not NVIDIA_API_EAI)
--   - Predicted digest matched actual mirror digest for both Boltz-2 and RFdiffusion
-- =============================================================================

CREATE OR REPLACE FUNCTION SCIENTIFIC_WORKBENCH.CATALOG.NIM_IMAGE_SIZE(
    repo VARCHAR,   -- e.g. 'nim/mit/boltz2' or 'nim/nvidia/genmol'
    tag  VARCHAR    -- e.g. '1.8.0' or 'latest'
)
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
PACKAGES = ('snowflake-snowpark-python', 'requests')
HANDLER = 'probe'
EXTERNAL_ACCESS_INTEGRATIONS = (NGC_REGISTRY_PULL_EAI)
SECRETS = ('ngc_key' = SCIENTIFIC_WORKBENCH.CATALOG.NGC_API_KEY)
COMMENT = 'Probe OCI manifest from nvcr.io: returns compressed size, layer count, digest. Also serves as entitlement check (401/403/404).'
AS
$$
import json, requests, _snowflake

REGISTRY = 'https://nvcr.io'

def probe(repo: str, tag: str) -> dict:
    api_key = _snowflake.get_generic_secret_string('ngc_key')

    # Step 1: Get auth token for the repository
    token_url = f'{REGISTRY}/v2/token?service=registry&scope=repository:{repo}:pull'
    token_resp = requests.get(token_url,
        auth=('$oauthtoken', api_key), timeout=30)

    if token_resp.status_code != 200:
        return {'status': token_resp.status_code, 'error': 'token_request_failed',
                'detail': token_resp.text[:200]}

    token = token_resp.json().get('token', '')

    # Step 2: Fetch manifest (may be multi-arch index or single manifest)
    headers = {
        'Authorization': f'Bearer {token}',
        'Accept': 'application/vnd.oci.image.index.v1+json, '
                  'application/vnd.docker.distribution.manifest.list.v2+json, '
                  'application/vnd.oci.image.manifest.v1+json, '
                  'application/vnd.docker.distribution.manifest.v2+json'
    }
    manifest_url = f'{REGISTRY}/v2/{repo}/manifests/{tag}'
    manifest_resp = requests.get(manifest_url, headers=headers, timeout=30)

    if manifest_resp.status_code != 200:
        return {'status': manifest_resp.status_code, 'error': 'manifest_fetch_failed',
                'detail': manifest_resp.text[:200]}

    manifest = manifest_resp.json()
    digest = manifest_resp.headers.get('Docker-Content-Digest', '')

    # Step 3: If multi-arch, resolve linux/amd64
    media_type = manifest.get('mediaType', '')
    if 'index' in media_type or 'manifest.list' in media_type:
        amd64_manifest = None
        for m in manifest.get('manifests', []):
            platform = m.get('platform', {})
            if platform.get('architecture') == 'amd64' and platform.get('os') == 'linux':
                amd64_manifest = m
                break
        if not amd64_manifest:
            return {'status': 200, 'error': 'no_amd64_manifest',
                    'architectures': [m.get('platform', {}).get('architecture', '?')
                                     for m in manifest.get('manifests', [])]}

        # Fetch the amd64-specific manifest
        amd64_digest = amd64_manifest['digest']
        amd64_resp = requests.get(
            f'{REGISTRY}/v2/{repo}/manifests/{amd64_digest}',
            headers={**headers, 'Accept': 'application/vnd.oci.image.manifest.v1+json, '
                     'application/vnd.docker.distribution.manifest.v2+json'},
            timeout=30)
        if amd64_resp.status_code != 200:
            return {'status': amd64_resp.status_code, 'error': 'amd64_manifest_failed'}
        manifest = amd64_resp.json()
        digest = amd64_digest

    # Step 4: Sum layer sizes
    layers = manifest.get('layers', [])
    total_bytes = sum(layer.get('size', 0) for layer in layers)
    total_gib = round(total_bytes / (1024 ** 3), 2)

    return {
        'status': 200,
        'repo': repo,
        'tag': tag,
        'compressed_gib': total_gib,
        'layers': len(layers),
        'digest': digest,
        'estimated_unpack_gib': round(total_gib * 3, 1),
        'fits_93gib_node': (total_gib * 3) < 75  # conservative: leave room for weights
    }
$$;
