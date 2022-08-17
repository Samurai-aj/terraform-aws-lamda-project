import boto3

import json

sfn = boto3.client('stepfunctions')

def lambda_handler(event, context ):
    
    sfn.start_execution(

         stateMachineArn="arn:aws:states:us-west-2:950053190816:stateMachine:my-state-machine",
         input=event['body']
        
        )
        
    return {
        "statusCode": 200,  
        "body": json.dumps( 
            {"Status": "Instruction sent to the REST API Handler!"},
        )
    }