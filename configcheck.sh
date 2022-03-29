# This script polls the configcheck endpoint until all the services return a "DONE" status.

echo "Waiting for all the services to be in a 'DONE' state before proceeding"
while [ 1 = 1 ]
do
    config_status=$(curl -k -H "Accept: application/vnd.github.v3+json" "https://api_key:${2}@${1}:8443/setup/api/configcheck" | jq '.progress[].status')
    echo "Config status is: ${config_status}"
    
    status_count=0
    # Loop through the status array
    for i in $config_status
    do
        eval i=$i
        # if it's done, increment the count
        if [ $i == "DONE" ];
        then
            ((status_count=status_count+1))
        fi
    done

    # If all the status are done, break out of the loop
    echo "Status count is: ${status_count}"
    if [ "$status_count" = 5 ];
    then
        break;
    else
        status_count=0
        echo "Still configuring, sleeping for 30 seconds"
        sleep 30
    fi
done

echo "All services are ready. Proceeding with config."