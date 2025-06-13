build:notify-failure:
  image: $APIGEE_FMK_MVN_IMAGE_NAME
  stage: notify
  when: on_failure
  allow_failure: true
  script:
    - echo "$CI_COMMIT_SHORT_SHA" > commit_id

    # Get JWT token
    - |
      JWT_TOKEN=$(curl --silent --location --request POST "$APIGEE_JWT_TOKEN_URL" \
        --header 'Content-Type: application/x-www-form-urlencoded' \
        --header 'Authorization: Basic YOUR_AUTH' \
        --data-urlencode 'alg=RS256' \
        --data-urlencode 'clientId=Mh9VKniW9rKVkBRZYoamGZ9k5hGCnrCq' \
        | grep -o '"access_token":"[^"]*' | sed 's/"access_token":"//')

    # Get failed jobs
    - curl --location --request GET "https://gitlab.onefiserv.net/api/v4/projects/$CI_PROJECT_ID/pipelines/$CI_PIPELINE_ID/jobs?scope[]=failed" \
        --header "PRIVATE-TOKEN:$PRIVATE_TOKEN" > failed_jobs.json

    # Build error details
    - echo "" > combined_logs.txt
    - |
      grep -o '"id":[0-9]*,"status":"failed".*web_url":"[^"]*"' failed_jobs.json | while read -r line; do
        JOB_ID=$(echo "$line" | grep -o '"id":[0-9]*' | cut -d':' -f2)
        JOB_NAME=$(echo "$line" | grep -o '"name":"[^"]*"' | cut -d':' -f2 | tr -d '"')
        JOB_STAGE=$(echo "$line" | grep -o '"stage":"[^"]*"' | cut -d':' -f2 | tr -d '"')
        echo "===== Job: $JOB_NAME =====" >> combined_logs.txt
        echo "Stage: $JOB_STAGE" >> combined_logs.txt
        echo "Log:" >> combined_logs.txt

        curl --silent --location --request GET \
          "https://gitlab.onefiserv.net/api/v4/projects/$CI_PROJECT_ID/jobs/$JOB_ID/trace" \
          --header "PRIVATE-TOKEN:$PRIVATE_TOKEN" >> combined_logs.txt

        echo -e "\\n----- End of Job $JOB_NAME -----\\n" >> combined_logs.txt
      done

    # Clean and escape logs
    - sed 's,\\x1B\\[[0-9;]*[a-zA-Z],,g;s/\r//' combined_logs.txt > cleaned_logs.txt
    - ERROR_DETAILS=$(cat cleaned_logs.txt | sed ':a;N;$!ba;s/\n/\\n/g')

    # Send to backend
    - |
      curl --location --request PUT "https://apihub.onefiserv.net/v1/apim-audit-logging/${PIPELINE_TYPE}/update-status" \
        --header 'Content-Type:application/json' \
        --header "Authorization: Bearer ${JWT_TOKEN}" \
        --data-raw "{\"trackingId\":\"${TRACKING_ID}\",\"commitId\":\"$(cat commit_id)\",\"pipelineStatus\":\"failed\",\"pipelineFailedStage\":\"multiple\",\"pipelineId\":\"${CI_PIPELINE_ID}\",\"pipelineErrorDetails\":\"${ERROR_DETAILS}\",\"pipelineType\":\"${PIPELINE_TYPE}\",\"projectId\":\"${CI_PROJECT_ID}\",\"refBranch\":\"${CI_COMMIT_REF_NAME}\"}"