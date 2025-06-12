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
    - |
      FAILED_STAGE=$(sed -n 's/.*"stage":"\([^"]*\)".*"web_url":"\([^"]*\)".*/\1/p' failed_jobs.json)
      ERROR_URL=$(sed -n 's/.*"stage":"\([^"]*\)".*"web_url":"\([^"]*\)".*/\2/p' failed_jobs.json)
      JOB_ID=$(echo $ERROR_URL | awk -F'/' '{print $NF}')
      curl --location --request GET "https://gitlab.onefiserv.net/api/v4/projects/$CI_PROJECT_ID/jobs/$JOB_ID/trace" \
        --header "PRIVATE-TOKEN:$PRIVATE_TOKEN" -s -o raw_logs.txt
    - sed 's/"//g' raw_logs.txt > logs_no_quotes.txt
    - sed 's,\x1B\[[0-9;]*[a-zA-Z],,g;s,\x0D\x0A,\x0A,g' logs_no_quotes.txt > cleaned_logs.txt
    - sed 's/$/#########/' cleaned_logs.txt > final_logs.txt
    - sed -e 's/\r/####/g' final_logs.txt > concatenated_logs.txt
    - |
      ERROR_DETAILS=$(cat concatenated_logs.txt)
      ERROR_DETAILS=$(printf "%s" "$ERROR_DETAILS" | sed ':a;N;$!ba;s/\n/\\n/g')
    - |
      curl --location --request PUT "https://apihub.onefiserv.net/v1/apim-audit-logging/${PIPELINE_TYPE}/update-status" \
        --header 'Content-Type:application/json' \
        --header "Authorization: Bearer ${JWT_TOKEN}" \
        --data-raw "{\"trackingId\":\"${TRACKING_ID}\",\"commitId\":\"$(cat commit_id)\",\"pipelineStatus\":\"failed\",\"pipelineFailedStage\":\"${FAILED_STAGE}\",\"pipelineId\":\"${CI_PIPELINE_ID}\",\"pipelineErrorDetails\":\"${ERROR_DETAILS}\",\"pipelineType\":\"${PIPELINE_TYPE}\",\"projectId\":\"${CI_PROJECT_ID}\",\"refBranch\":\"${CI_COMMIT_REF_NAME}\"}"