#! /bin/bash

echo "calling digitalocean api to create a new instance and run cloud-init ..."

api_response_code=$(curl -s -o tmp/create_instance_api_response.txt -w "%{http_code}" -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $DIGITALOCEAN_TOKEN" \
  -d '{"name":"instance-from-api-call-with-cloud-init-ansible-playbook.com","region":"nyc1","size":"s-1vcpu-1gb","image":"ubuntu-20-04-x64","ssh_keys":["0a:bf:e1:1c:52:e8:3f:75:45:85:c8:f2:00:b7:3a:4b"],"backups":false,"ipv6":false,"user_data":"#cloud-config\nruncmd:\n  - echo updating SSH port to 4444 ...\n  - sed -i -e '\''/^#Port/s/^.*$/Port 4444/'\'' /etc/ssh/sshd_config\n  - echo restating SSH server ...\n  - systemctl restart sshd","private_networking":null,"volumes": null,"tags":["from_api_call"]}' \
  "https://api.digitalocean.com/v2/droplets")

# add new created instance_id to the config
if [ $api_response_code == "202" ]; then
  instance_id=$(cat tmp/create_instance_api_response.txt | jq '.droplet.id')
  echo "api call successfull instance_id: $instance_id, waiting for instnace to be finished ... "

  echo "sleeping 10 seconds before continue ..." 
  sleep 10

  # check if instance is ready
  new_instance_public_ip_address=""
  while [ "$new_instance_public_ip_address" == "" ] || [ "$new_instance_public_ip_address" == "null" ]; do
    echo "instance($instance_id) creation is still pending, sleeping 5 seconds before checking again ..."
    sleep 5
    new_instance_status=$(curl -X GET -H "Content-Type: application/json"   -H "Authorization: Bearer $DIGITALOCEAN_TOKEN"   "https://api.digitalocean.com/v2/droplets/$instance_id" | jq -r '.droplet.status')
    echo current instance status: $new_instance_status
    if [ $new_instance_status == "active" ]; then
      sleep 5
      echo "instance is ready getting public ip address ..."
      new_instance_public_ip_address=$(curl -X GET  -H "Content-Type: application/json"  -H "Authorization: Bearer $DIGITALOCEAN_TOKEN"   "https://api.digitalocean.com/v2/droplets/$instance_id" | jq -r '.droplet.networks.v4[0].ip_address')
    fi
  done

  # at this point we have new instance ip address, now we can run our tests
  echo "instance created successfully, public ip address: $new_instance_public_ip_address"

  # if instance is ready then try to connect on port 4444
  port=4444
  echo "trying to connect to digitalocean with ssh on port $port"

  success=""
  for run in {1..10}; do
    ssh -i ~/.ssh/dev/digitalocean/id_rsa root@$new_instance_public_ip_address -p $port exit
    if [ $? == 255 ]; then
      echo "unable to connect on port $port, trying again after 5 seconds ..."
      sleep 5
    else
      success="ok"
      echo "connection successull on $port, test is success!"
      break
    fi
  done

  if [ "$success" != "ok" ]; then
    echo "unable to connect on port $port, test failed ..."
  fi
fi


