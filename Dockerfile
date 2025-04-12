FROM public.ecr.awslambdanodejs16

# Copy function code
COPY patient-service.js ${LAMBDA_TASK_ROOT}
COPY appointment-service.js ${LAMBDA_TASK_ROOT}

# Command to run the Lambda function
CMD [app.handler]