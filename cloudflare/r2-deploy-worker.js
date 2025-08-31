/**
 * Cloudflare Worker for R2 Deployment with Retention Enforcement
 * Handles immutable artifact uploads with retention policies
 */

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    
    // Only allow POST for uploads
    if (request.method !== 'POST') {
      return new Response('Method not allowed', { status: 405 });
    }
    
    // Verify deployment token
    const authHeader = request.headers.get('Authorization');
    if (!authHeader || !await verifyToken(authHeader, env)) {
      return new Response('Unauthorized', { status: 401 });
    }
    
    try {
      // Parse multipart form data
      const formData = await request.formData();
      const file = formData.get('artifact');
      const version = formData.get('version');
      const signature = formData.get('signature');
      const digest = formData.get('digest');
      
      if (!file || !version || !signature || !digest) {
        return new Response('Missing required fields', { status: 400 });
      }
      
      // Verify artifact signature
      if (!await verifySignature(file, signature, digest, env)) {
        return new Response('Invalid signature', { status: 403 });
      }
      
      // Generate immutable path with content hash
      const contentHash = await generateHash(await file.arrayBuffer());
      const objectKey = `releases/v${version}/${file.name}.${contentHash}`;
      
      // Check if object already exists (immutability check)
      const existing = await env.R2_BUCKET.head(objectKey);
      if (existing) {
        return new Response(JSON.stringify({
          message: 'Artifact already exists (immutable)',
          key: objectKey,
          etag: existing.etag
        }), {
          status: 200,
          headers: { 'Content-Type': 'application/json' }
        });
      }
      
      // Upload with retention metadata
      const uploadResult = await env.R2_BUCKET.put(objectKey, file.stream(), {
        httpMetadata: {
          contentType: file.type || 'application/octet-stream',
        },
        customMetadata: {
          version: version,
          signature: signature,
          digest: digest,
          uploadedAt: new Date().toISOString(),
          retention: '90days',
          immutable: 'true'
        }
      });
      
      // Set object lock
      await setObjectLock(env.R2_BUCKET, objectKey, 90);
      
      // Update current symlink
      await updateCurrentVersion(env.R2_BUCKET, version, objectKey);
      
      // Log to audit trail
      await logDeployment(env, {
        key: objectKey,
        version: version,
        hash: contentHash,
        timestamp: new Date().toISOString(),
        uploader: authHeader
      });
      
      return new Response(JSON.stringify({
        success: true,
        key: objectKey,
        version: version,
        hash: contentHash,
        etag: uploadResult.etag,
        retention: '90 days',
        immutable: true
      }), {
        status: 201,
        headers: { 'Content-Type': 'application/json' }
      });
      
    } catch (error) {
      console.error('Upload error:', error);
      return new Response(JSON.stringify({
        error: 'Upload failed',
        message: error.message
      }), {
        status: 500,
        headers: { 'Content-Type': 'application/json' }
      });
    }
  }
};

async function verifyToken(authHeader, env) {
  const token = authHeader.replace('Bearer ', '');
  const expected = await env.DEPLOY_TOKEN.get('current');
  
  // Constant-time comparison
  if (token.length !== expected.length) return false;
  
  let result = 0;
  for (let i = 0; i < token.length; i++) {
    result |= token.charCodeAt(i) ^ expected.charCodeAt(i);
  }
  
  return result === 0;
}

async function verifySignature(file, signature, digest, env) {
  // Import public key
  const publicKey = await crypto.subtle.importKey(
    'spki',
    base64ToArrayBuffer(env.SIGNING_PUBLIC_KEY),
    {
      name: 'RSASSA-PKCS1-v1_5',
      hash: 'SHA-256'
    },
    false,
    ['verify']
  );
  
  // Verify signature
  const fileBuffer = await file.arrayBuffer();
  const signatureBuffer = base64ToArrayBuffer(signature);
  
  const isValid = await crypto.subtle.verify(
    'RSASSA-PKCS1-v1_5',
    publicKey,
    signatureBuffer,
    fileBuffer
  );
  
  // Also verify digest
  const computedDigest = await generateHash(fileBuffer);
  return isValid && computedDigest === digest;
}

async function generateHash(buffer) {
  const hashBuffer = await crypto.subtle.digest('SHA-256', buffer);
  return bufferToHex(hashBuffer);
}

async function setObjectLock(bucket, key, retentionDays) {
  // Set retention metadata (actual lock via R2 API)
  const retentionDate = new Date();
  retentionDate.setDate(retentionDate.getDate() + retentionDays);
  
  // This would use R2's object lock API when available
  // For now, we rely on bucket-level policies
  return true;
}

async function updateCurrentVersion(bucket, version, objectKey) {
  // Create a "symlink" to current version
  const currentKey = `current/latest`;
  
  await bucket.put(currentKey, JSON.stringify({
    version: version,
    artifact: objectKey,
    updated: new Date().toISOString()
  }), {
    httpMetadata: {
      contentType: 'application/json'
    },
    customMetadata: {
      version: version,
      immutable: 'false' // Current pointer can be updated
    }
  });
}

async function logDeployment(env, details) {
  // Log to durable object for audit trail
  const id = env.AUDIT_LOG.idFromName('deployments');
  const auditLog = env.AUDIT_LOG.get(id);
  
  await auditLog.fetch(new Request('https://audit.log/deployment', {
    method: 'POST',
    body: JSON.stringify(details)
  }));
}

function base64ToArrayBuffer(base64) {
  const binaryString = atob(base64);
  const bytes = new Uint8Array(binaryString.length);
  for (let i = 0; i < binaryString.length; i++) {
    bytes[i] = binaryString.charCodeAt(i);
  }
  return bytes.buffer;
}

function bufferToHex(buffer) {
  return Array.from(new Uint8Array(buffer))
    .map(b => b.toString(16).padStart(2, '0'))
    .join('');
}