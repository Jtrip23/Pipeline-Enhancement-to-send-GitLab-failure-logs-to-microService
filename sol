build:notify-failure:
  image: $APIGEE_FMK_MVN_IMAGE_NAME
  stage: notify
  when: on_failure
  allow_failure: true
  script:
    - echo "$CI_COMMIT_SHORT_SHA" > commit_id
    - |
      JWT_TOKEN=$(curl --silent --location --request POST "$APIGEE_JWT_TOKEN_URL" \
        --header 'Content-Type: application/x-www-form-urlencoded' \
        --header 'Authorization: Basic TWg5VktuaVc5cktWa0JSWllvYW1HWjlrNWhHQ25yQ3E6cE5WalBkQmduNzZ2MUkwQTloQkZSQkd0aTRpaHhrMWpPc0FvOU1MWmdPUg==' \
        --data-urlencode 'alg=RS256' \
        --data-urlencode 'clientId=Mh9VKniW9rKVkBRZYoamGZ9k5hGCnrCq' | grep -o '"access_token":"[^"]*' | sed 's/"access_token":"//' | tr -d '"')
    - |
      curl --location --request GET "https://gitlab.onefiserv.net/api/v4/projects/$CI_PROJECT_ID/pipelines/$CI_PIPELINE_ID/jobs?scope[]=failed" \
        --header "PRIVATE-TOKEN:$PRIVATE_TOKEN" > failed_jobs.json
    - echo "[" > structured_logs.json
    - |
      job_count=$(jq length failed_jobs.json)
      for i in $(seq 0 $((job_count - 1))); do
        job_id=$(jq -r ".[$i].id" failed_jobs.json)
        job_name=$(jq -r ".[$i].name" failed_jobs.json)
        job_stage=$(jq -r ".[$i].stage" failed_jobs.json)

        curl --silent --location --request GET \
          "https://gitlab.onefiserv.net/api/v4/projects/$CI_PROJECT_ID/jobs/$job_id/trace" \
          --header "PRIVATE-TOKEN:$PRIVATE_TOKEN" -o job_trace.txt

        job_log=$(cat job_trace.txt | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\\n/\\\\n/g')

        echo "{\"jobName\": \"$job_name\", \"stage\": \"$job_stage\", \"log\": \"$job_log\"}," >> structured_logs.json
      done
    - sed -i '$ s/,$//' structured_logs.json
    - echo "]" >> structured_logs.json
    - ERROR_DETAILS=$(cat structured_logs.json)
    - |
      curl --location --request PUT "https://apihub.onefiserv.net/v1/apim-audit-logging/${PIPELINE_TYPE}/update-status" \
        --header 'Content-Type:application/json' \
        --header "Authorization: Bearer ${JWT_TOKEN}" \
        --data-raw "{\"trackingId\":\"${TRACKING_ID}\",\"commitId\":\"$(cat commit_id)\",\"pipelineStatus\":\"failed\",\"pipelineFailedStage\":\"multiple\",\"pipelineId\":\"${CI_PIPELINE_ID}\",\"pipelineErrorDetails\":${ERROR_DETAILS},\"pipelineType\":\"${PIPELINE_TYPE}\",\"projectId\":\"${CI_PROJECT_ID}\",\"refBranch\":\"${CI_COMMIT_REF_NAME}\"}"