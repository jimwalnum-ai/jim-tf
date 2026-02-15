This file creates an S3 bucket which will be used to store terraform state for the next steps.
It uses modules to instantiate resources. Modules provide a way to share standard resource setups or ensure
that those resources are created with certain defaults. 


All buckets should be encrypted by default. Having data encrypted at rest and in flight is a central
requirment for many audit frameworks. In addition, if you wish to possibly share a bucket across AWS
account, you must use a KMS key. The default SSE encyrption cannot be used cross account.

This modues create a KMS key and an associated key policy that allows the roles passed 
in the lists below. See the detail of the module definition in the modules "source" path

[KMS Module](https://gitlab.com/cs-devel/crimsonscallion/-/tree/main/modules/kms)

```
module "backend-kms-key" {
  source = "../modules/kms"
  key_name = "cs-use1-backend-s3-kms"
  readonly_roles = ["arn:aws:iam::${local.acct_id}:user/cloud_user",
                    "arn:aws:iam::${local.acct_id}:role/cs-terraform-role"]
  write_roles = ["arn:aws:iam::${local.acct_id}:root"]
}
```

[S3 Module](https://gitlab.com/cs-devel/crimsonscallion/-/tree/main/modules/s3)
The bucket_policy argument is not set here since it is set in the aws_s3_bucket_policy resource below

```
module "s3" {
 source = "../modules/s3"
 bucket_name = local.state_bucket_name
 bucket_policy = ""
 kms_key = module.backend-kms-key.kms_key_arn
 versioning = "Enabled"
 tags = local.tags
}
```

[Template Files](https://gitlab.com/cs-devel/crimsonscallion/-/tree/main/1_the_basics/templates)
The templates takes arguments for bucket_name and principal

```
data "template_file" "s3_policy" {
  template = "${file("./templates/s3_tf_bucket_policy.json.tpl")}"
  vars = {
    bucket_name   = module.s3.bucket_name
    tf_user_arn = "arn:aws:iam::${local.acct_id}:user/cloud_user"
  }
}
```

This sets the policy for the s3 bucket holding the state files by associating the rendered policy the the bucket

```
resource "aws_s3_bucket_policy" "policy" {
  bucket = module.s3.bucket_name
  policy = data.template_file.s3_policy.rendered
}
```




