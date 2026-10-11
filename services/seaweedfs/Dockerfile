# SeaweedFS S3 store for PostHog on Railway (used twice in the template:
# `objectstorage` for exports/media/AI blobs and `seaweedfs` for session recordings).
# PostHog's Node and Rust S3 clients force path-style requests against custom
# endpoints, which Railway Buckets (virtual-hosted style) do not accept, so the
# template keeps PostHog's own SeaweedFS layout instead of a Railway Bucket.
FROM chrislusf/seaweedfs:4.48

COPY railway-seaweedfs.sh /usr/local/bin/railway-seaweedfs.sh
RUN chmod 0755 /usr/local/bin/railway-seaweedfs.sh

EXPOSE 8333 19000

ENTRYPOINT ["/usr/local/bin/railway-seaweedfs.sh"]
