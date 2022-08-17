#read data from already created aws lamba role
data "aws_iam_role" "lambda-role" {

    name = "lambda"
}
#iam role for step functions
data "aws_iam_role" "step-function-role" { 
    name = "SendingRole"

}
#lambda function to send email
resource "aws_lambda_function" "email" {

    filename = "${path.module}/email-function.zip" 
    function_name = "email"
    role = data.aws_iam_role.lambda-role.arn
    runtime = "python3.9"
    source_code_hash = filebase64sha256("${path.module}/email-function.zip") 
    handler = "email.lambda_handler"   
}

#lambda function to send sms
resource "aws_lambda_function" "sms" {

    filename = "${path.module}/sms-function.zip"
    function_name = "sms"
    role = data.aws_iam_role.lambda-role.arn
    runtime = "python3.9"
    source_code_hash = filebase64sha256("${path.module}/sms-function.zip")
    handler = "sms.lambda_handler"

}

#aws step function to recieve payload from restapihandler and decide on what functio to invoke
resource "aws_sfn_state_machine" "step-function" {
      name     = "my-state-machine"
      role_arn = data.aws_iam_role.step-function-role.arn
      type= "STANDARD"
      definition = <<EOF


         {
            "Comment": "State machine for sending SMS & email",
            "StartAt": "Select Type of Sending",
            "States": {
                "Select Type of Sending": {
                    "Type": "Choice",
                    "Choices": [
                        {

                            "Variable": "$.typeOfSending",
                            "StringEquals": "email",
                            "Next": "Email"
                        },
                     {
                            "Variable": "$.typeOfSending",
                            "StringEquals": "sms",
                            "Next": "SMS"
                     }
                    ]
             },
                "Email": {
                    "Type" : "Task",
                    "Resource": "${aws_lambda_function.email.arn}",
                    "End": true
                },
                "SMS": {
                    "Type" : "Task",
                    "Resource": "${aws_lambda_function.sms.arn}",
                    "End": true
                }
            }
        }
      EOF

}

#create lambda api handler that recieves the body sent by the api
resource "aws_lambda_function" "rest-api-handler" {

    filename = "${path.module}/rest-apihandler.zip"
    function_name = "rest-apihandler"
    role = data.aws_iam_role.lambda-role.arn
    runtime = "python3.9"
    source_code_hash = filebase64sha256("${path.module}/rest-apihandler.zip")
    handler = "rest-apihandler.lambda_handler"   

}



#create the rest api 
resource "aws_api_gateway_rest_api" "sending-api" {

    name = "sending"
    description = "this is a simple api to send sms and recieve emails and sms"
    endpoint_configuration {
    types = ["REGIONAL"]
    
    } 
}

#create the rest api resource
resource "aws_api_gateway_resource" "sending-resource" {

    rest_api_id = aws_api_gateway_rest_api.sending-api.id
    parent_id = aws_api_gateway_rest_api.sending-api.root_resource_id
    path_part   = "sending"
  
}

#create the method used to access the api
resource "aws_api_gateway_method" "sending-method" {

    rest_api_id = aws_api_gateway_rest_api.sending-api.id
    resource_id = aws_api_gateway_resource.sending-resource.id
    http_method = "POST"
    authorization = "NONE"
}

#integrate the api created with the lambda api handler
resource "aws_api_gateway_integration" "sending-integration" {

    rest_api_id = "${aws_api_gateway_rest_api.sending-api.id}"
    resource_id = "${aws_api_gateway_resource.sending-resource.id}"
    http_method = "${aws_api_gateway_method.sending-method.http_method}"
    type = "AWS_PROXY"
    uri = aws_lambda_function.rest-api-handler.invoke_arn
    integration_http_method   = "POST"
  
}

#give api integration permission to invoke lambda
resource "aws_lambda_permission" "apigw-lambda" {
     statement_id  = "AllowExecutionFromAPIGateway"
     action        = "lambda:InvokeFunction"
     function_name = aws_lambda_function.rest-api-handler.function_name
     principal = "apigateway.amazonaws.com"

      # The /*/*/* part allows invocation from any stage, method and resource path
      # within API Gateway REST API.
     source_arn =  "${aws_api_gateway_rest_api.sending-api.execution_arn}/*/*/*"
     
}

#finally deploy the api
resource "aws_api_gateway_deployment" "sending-deployment" {
  rest_api_id = aws_api_gateway_rest_api.sending-api.id
  
  #values that when changed will trigger a redeployment of the api
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.sending-resource.id,
      aws_api_gateway_method.sending-method.id,
      aws_api_gateway_integration.sending-integration.id,

    ]))
  }


   
  lifecycle {
    create_before_destroy = true
  }

}

#create api gateway stage
resource "aws_api_gateway_stage" "sendingStage" {
  deployment_id = aws_api_gateway_deployment.sending-deployment.id
  rest_api_id   = aws_api_gateway_rest_api.sending-api.id
  stage_name    = "sendingStage"
}






