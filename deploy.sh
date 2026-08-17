#!/bin/bash
set -e
CLOUDFRONT_ID="E2TOLHG1XYMDUD"
S3_BUCKET="cuisinecoord-philmathieu-web"
API_URL=$(cd infra && terraform output -raw api_url 2>/dev/null || echo "")

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -z "$PLACES_KEY" ] && [ -f "$SCRIPT_DIR/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/.env"
  set +a
fi

if [ -z "$PLACES_KEY" ]; then
  echo "Error: PLACES_KEY environment variable is not set." >&2
  echo "Set it to your Google Places/Maps API key before deploying," >&2
  echo "or create a .env file (see .env — gitignored) with PLACES_KEY=..." >&2
  exit 1
fi

echo "Building..."
flutter build web --release \
  ${API_URL:+--dart-define=API_URL=$API_URL} \
  --dart-define=PLACES_KEY=$PLACES_KEY

echo "Uploading to S3..."
aws s3 sync build/web/ s3://$S3_BUCKET/ --delete --quiet

echo "Invalidating CloudFront..."
aws cloudfront create-invalidation --distribution-id $CLOUDFRONT_ID --paths "/*" --query 'Invalidation.Status' --output text
echo "Done. Live at https://cuisinecoord.philmathieu.com"
