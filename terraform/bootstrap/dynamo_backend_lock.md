This defines a dynamodb table that is used as a semaphore
that only allows one process to modify state at a time. Any process that could
possibly modify the state uses the lock table. DynamoDb is a common lock for AWS.
It must have LockID as the hash and attribute

```
resource "aws_dynamodb_table" "dynamodb-terraform-state-lock" {
  name = "terraform-lock-dynamo"
  hash_key = "LockID"
  read_capacity = 20
  write_capacity = 20
 
  attribute {
    name = "LockID"
    type = "S"
  }
}
```