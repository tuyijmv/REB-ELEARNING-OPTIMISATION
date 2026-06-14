#!/bin/sh
set -e

# Wait for MinIO to be ready
echo "Waiting for MinIO to be ready..."
sleep 5

# Configure MinIO client
mc alias set myminio http://localhost:9000 ${MINIO_ROOT_USER} ${MINIO_ROOT_PASSWORD}

# Create bucket if it doesn't exist
BUCKET_NAME=${MINIO_BUCKET:-moodle}
if mc ls myminio/${BUCKET_NAME} >/dev/null 2>&1; then
    echo "Bucket '${BUCKET_NAME}' already exists"
else
    echo "Creating bucket '${BUCKET_NAME}'..."
    mc mb myminio/${BUCKET_NAME}
    echo "Bucket '${BUCKET_NAME}' created successfully"
fi

# Set public policy for the bucket (adjust based on your security requirements)
echo "Setting bucket policy..."
mc anonymous set download myminio/${BUCKET_NAME}

# Set public policy specifically for resources folder
echo "Setting public policy for resources folder..."
mc anonymous set download myminio/${BUCKET_NAME}/resources

# Enable versioning (optional, useful for file recovery)
echo "Enabling versioning..."
mc version enable myminio/${BUCKET_NAME}

# Configure CORS to allow uploads from Moodle frontend
echo "Configuring CORS..."
cat > /tmp/cors.json <<EOF
{
  "CORSRules": [
    {
      "AllowedOrigins": ["http://localhost:8080", "http://127.0.0.1:8080"],
      "AllowedMethods": ["GET", "PUT", "POST", "HEAD", "DELETE"],
      "AllowedHeaders": ["*"],
      "ExposeHeaders": ["ETag", "Content-Length", "Content-Type"]
    }
  ]
}
EOF

mc admin config set myminio api cors_allow_origin="http://localhost:8080,http://127.0.0.1:8080"

echo "MinIO initialization completed successfully!"
