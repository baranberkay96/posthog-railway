#!/bin/sh
# All-in-one SeaweedFS (master + volume + filer + S3 gateway) with:
# - S3 credentials from AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY (SeaweedFS reads
#   them as an admin identity, so unsigned requests are rejected),
# - the buckets listed in S3_BUCKETS created once the master is up (idempotent),
# - data on the Railway volume mounted at /data.
set -eu

S3_PORT="${S3_PORT:-8333}"
S3_BUCKETS="${S3_BUCKETS:-posthog}"

if [ -z "${AWS_ACCESS_KEY_ID:-}" ] || [ -z "${AWS_SECRET_ACCESS_KEY:-}" ]; then
  echo "FATAL: AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY must be set." >&2
  exit 1
fi

mkdir -p /data
rm -rf /data/lost+found 2>/dev/null || true

create_buckets() {
  for bucket in $(echo "$S3_BUCKETS" | tr ',' ' '); do
    until echo "s3.bucket.list" | weed shell -master=localhost:9333 2>/dev/null | grep -qw "$bucket"; do
      echo "s3.bucket.create -name $bucket" | weed shell -master=localhost:9333 >/dev/null 2>&1 || true
      sleep 2
    done
    echo "railway: bucket '$bucket' ready"
  done
}

create_buckets &

echo "railway: starting SeaweedFS S3 on port ${S3_PORT} (buckets: ${S3_BUCKETS})"
exec weed server \
  -dir=/data \
  -ip=127.0.0.1 \
  -ip.bind=:: \
  -master.volumePreallocate=false \
  -volume.max=1000 \
  -s3 \
  -s3.port="${S3_PORT}"
