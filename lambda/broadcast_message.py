import json
import boto3
import os

from botocore.exceptions import ClientError

def broadcast_message(event, context):
    api_gw = boto3.client(
        'apigatewaymanagementapi', 
        region_name="us-west-1", # TODO: turn this to env
        endpoint_url=os.getenv("apigw_https_url"))
    print(event)

    dynamodb = boto3.resource('dynamodb')
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

        # NOTE: Maybe store a region field in dynamo so this loop is slightly more efficient?
        for connection in connections:
            try:
                api_gw.post_to_connection(
                    ConnectionId=connection["connectionId"], 
                    Data=body['Message'],
                )
            except ClientError as e:
                error_code = e.response['Error']['Code']
                if error_code in ("GoneException", "Gone"):
                    print(f"Connection {connection} is in different region. Skipped.")
                else:
                    print(e)

    
    return {
        'statusCode': 200,
    }
