#!/bin/bash
set -e
CLOUDFRONT_ID="E2TOLHG1XYMDUD"
S3_BUCKET="cuisinecoord-philmathieu-web"
API_URL=$(cd infra && terraform output -raw api_url 2>/dev/null || echo "")

echo "Building..."
flutter build web --release ${API_URL:+--dart-define=API_URL=$API_URL}

echo "Uploading to S3..."
aws s3 sync build/web/ s3://$S3_BUCKET/ --delete --quiet

echo "Invalidating CloudFront..."
aws cloudfront create-invalidation --distribution-id $CLOUDFRONT_ID --paths "/*" --query 'Invalidation.Status' --output text
echo "Done. Live at https://cuisinecoord.philmathieu.com"
