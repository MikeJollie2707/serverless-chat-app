import json
import boto3
import os

def broadcast_message(event, context):
    api_gw = boto3.client(
        'apigatewaymanagementapi', 
        region_name="us-west-1", 
        endpoint_url=os.getenv("apigw_https_url"))
    print(event)

    dynamodb = boto3.resource('dynamodb', region_name='us-west-1')
    connectionTable = dynamodb.Table(os.getenv("connectionTableName"))
    response = connectionTable.scan()
    connections = response.get("Items", [])
    print(connections)
    
    records = event['Records']
    for message in records:
        body = json.loads(message['body'])
        print(body['Message'])
        # author, timestamp, etc.
        # print(body['MessageAttributes'])

        # NOTE: May need to store region of a connection ID
        # cuz if user connect from different gateways, that connectionID
        # is not usable on the same api_gw
        for connection in connections:
            api_gw.post_to_connection(
                ConnectionId=connection["connectionId"], 
                Data=body['Message'],
            )

    
    return {
        'statusCode': 200,
    }
