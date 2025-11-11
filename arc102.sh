#!/bin/bash

# Color Definitions
BLACK_TEXT=$'\033[0;90m'
RED_TEXT=$'\033[0;91m'
GREEN_TEXT=$'\033[0;92m'
YELLOW_TEXT=$'\033[0;93m'
BLUE_TEXT=$'\033[0;94m'
MAGENTA_TEXT=$'\033[0;95m'
CYAN_TEXT=$'\033[0;96m'
WHITE_TEXT=$'\033[0;97m'

NO_COLOR=$'\033[0m'
RESET_FORMAT=$'\033[0m'
BOLD_TEXT=$'\033[1m'
UNDERLINE_TEXT=$'\033[4m'

# Display Welcome Message
print_welcome() {
echo "${BLUE_TEXT}${BOLD_TEXT}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${RESET_FORMAT}"
echo "${BLUE_TEXT}${BOLD_TEXT}┃           C l o u d o A r c          ┃${RESET_FORMAT}"
echo "${BLUE_TEXT}${BOLD_TEXT}┃               Cloud Lab              ┃${RESET_FORMAT}"
echo "${BLUE_TEXT}${BOLD_TEXT}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${RESET_FORMAT}"
echo
}

# Display Completion Message
print_completion() {
  echo
echo "${GREEN_TEXT}${BOLD_TEXT}=======================================================${RESET_FORMAT}"
echo "${GREEN_TEXT}${BOLD_TEXT}               LAB COMPLETED SUCCESSFULLY!!!           ${RESET_FORMAT}"
echo "${GREEN_TEXT}${BOLD_TEXT}=======================================================${RESET_FORMAT}"
echo

# ====== GCP DECODE Footer ======
echo "${RED_TEXT}${BOLD_TEXT}🎥 Watch more labs on:  ${RESET_FORMAT}"
echo "${WHITE_TEXT}${BOLD_TEXT}CloudoArc — YouTube${RESET_FORMAT}"
}



# Get User Input with Validation
read -p "${RED_TEXT}${BOLD_TEXT}Bucket Name: ${RESET_FORMAT}" BUCKET_NAME
echo "${YELLOW_TEXT}${BOLD_TEXT}Bucket Name: $BUCKET_NAME ${RESET_FORMAT}"
echo

read -p "${RED_TEXT}${BOLD_TEXT}Topic Name: ${RESET_FORMAT}" TOPIC_NAME
echo "${YELLOW_TEXT}${BOLD_TEXT}Topic Name: $TOPIC_NAME ${RESET_FORMAT}"
echo

read -p "${RED_TEXT}${BOLD_TEXT}Cloud Function Name: ${RESET_FORMAT}" FUNCTION_NAME
echo "${YELLOW_TEXT}${BOLD_TEXT}Function Name: $FUNCTION_NAME ${RESET_FORMAT}"
echo

read -p "${RED_TEXT}${BOLD_TEXT}Enter Region: ${RESET_FORMAT}" REGION
echo "${YELLOW_TEXT}${BOLD_TEXT}Region: $REGION ${RESET_FORMAT}"
echo

# Set Configuration
gcloud config set compute/region $REGION
export PROJECT_ID=$(gcloud config get-value project)

# Enable Required Services
echo
echo "${RED_TEXT}${BOLD_TEXT}Enabling Google Cloud Services...${RESET_FORMAT}"
gcloud services enable \
  artifactregistry.googleapis.com \
  cloudfunctions.googleapis.com \
  cloudbuild.googleapis.com \
  eventarc.googleapis.com \
  run.googleapis.com \
  logging.googleapis.com \
  pubsub.googleapis.com

# Create Infrastructure
echo
echo "${RED_TEXT}${BOLD_TEXT}Creating Storage Bucket...${RESET_FORMAT}"
gsutil mb -l $REGION gs://$BUCKET_NAME

echo
echo "${RED_TEXT}${BOLD_TEXT}Creating Topic...${RESET_FORMAT}"
gcloud pubsub topics create $TOPIC_NAME

# Configure Permissions
PROJECT_NUMBER=$(gcloud projects list --filter="project_id:$PROJECT_ID" --format='value(project_number)')
SERVICE_ACCOUNT=$(gsutil kms serviceaccount -p $PROJECT_NUMBER)

echo
echo "${RED_TEXT}${BOLD_TEXT}Configuring Permissions...${RESET_FORMAT}"
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member serviceAccount:$SERVICE_ACCOUNT \
  --role roles/pubsub.publisher

# Create Function Files
echo
echo "${RED_TEXT}${BOLD_TEXT}Preparing Function...${RESET_FORMAT}"
mkdir -p ~/cloud-thumbnail-function && cd $_
touch index.js package.json

# Generate index.js
cat > index.js <<'EOF_END'
const crc32 = require("fast-crc32c");
const { Storage } = require('@google-cloud/storage');
const gcs = new Storage();
const { PubSub } = require('@google-cloud/pubsub');
const imagemagick = require("imagemagick-stream");

exports.thumbnail = (event, context) => {
  const fileName = event.name;
  const bucketName = event.bucket;
  const size = "64x64";
  const bucket = gcs.bucket(bucketName);
  const topicName = "TOPIC_NAME_PLACEHOLDER";
  const pubsub = new PubSub();

  if (fileName.search("64x64_thumbnail") == -1) {
    const filename_split = fileName.split('.');
    const filename_ext = filename_split[filename_split.length - 1];
    const filename_without_ext = fileName.substring(0, fileName.length - filename_ext.length);
    
    if (filename_ext.toLowerCase() == 'png' || filename_ext.toLowerCase() == 'jpg') {
      console.log(`Processing: gs://${bucketName}/${fileName}`);
      const gcsObject = bucket.file(fileName);
      const newFilename = filename_without_ext + size + '_thumbnail.' + filename_ext;
      const gcsNewObject = bucket.file(newFilename);
      const srcStream = gcsObject.createReadStream();
      const dstStream = gcsNewObject.createWriteStream();
      const resize = imagemagick().resize(size).quality(90);
      
      srcStream.pipe(resize).pipe(dstStream);
      
      return new Promise((resolve, reject) => {
        dstStream
          .on("error", (err) => {
            console.error(`Error: ${err}`);
            reject(err);
          })
          .on("finish", () => {
            console.log(`Created thumbnail: ${newFilename}`);
            gcsNewObject.setMetadata({
              contentType: 'image/' + filename_ext.toLowerCase()
            }, (err) => {
              if (err) console.error('Metadata error:', err);
            });
            
            pubsub.topic(topicName)
              .publisher()
              .publish(Buffer.from(newFilename))
              .then(messageId => {
                console.log(`Published message ID: ${messageId}`);
              })
              .catch(err => {
                console.error('Publish error:', err);
              });
          });
      });
    } else {
      console.log(`Skipping: ${fileName} - Unsupported image format`);
    }
  } else {
    console.log(`Skipping: ${fileName} - Already has thumbnail`);
  }
};
EOF_END

# Customize the function code
sed -i "s/TOPIC_NAME_PLACEHOLDER/$TOPIC_NAME/" index.js

# Generate package.json
cat > package.json <<EOF_END
{
  "name": "thumbnail-generator",
  "version": "1.0.0",
  "description": "Google Cloud Function to generate image thumbnails",
  "scripts": {
    "start": "node index.js"
  },
  "dependencies": {
    "@google-cloud/pubsub": "^2.0.0",
    "@google-cloud/storage": "^5.0.0",
    "fast-crc32c": "1.0.4",
    "imagemagick-stream": "4.1.1"
  },
  "engines": {
    "node": ">=12.0.0"
  }
}
EOF_END

# Deploy Function
deploy_function() {
  echo
  echo "${RED_TEXT}${BOLD_TEXT}Cloud Function On The Way...${RESET_FORMAT}"
  gcloud functions deploy $FUNCTION_NAME \
    --gen2 \
    --runtime nodejs20 \
    --entry-point thumbnail \
    --source . \
    --region $REGION \
    --trigger-bucket $BUCKET_NAME \
    --allow-unauthenticated \
    --trigger-location $REGION \
    --max-instances 5 \
    --quiet
}

# Wait for deployment to complete
while true; do
  if deploy_function; then
    if gcloud functions describe $FUNCTION_NAME --region $REGION &> /dev/null; then
      break
    fi
  fi
  echo "${RED_TEXT}${BOLD_TEXT}Waiting for deployment...${RESET_FORMAT}"
  sleep 10
done

# Test with sample image
echo
echo "${RED_TEXT}${BOLD_TEXT}Testing...${RESET_FORMAT}"
wget -q https://storage.googleapis.com/cloud-training/arc102/wildlife.jpg
gsutil cp wildlife.jpg gs://$BUCKET_NAME

print_completion
