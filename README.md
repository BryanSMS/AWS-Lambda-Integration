# AWS + Lambda Integration

Pipeline serverless que recibe una imagen, la guarda en S3 y la recorta
en círculo con Lambda y SQS. Infraestructura en Terraform,
desplegable en DEV, QA y PROD.

## Requisitos
- AWS CLI v2 con un perfil SSO configurado
- Terraform >= 1.5
- Node.js 20

## Despliegue
1. Cambia `aws_profile` en `variables.tf` o pasa `-var="aws_profile=TU_PERFIL"`.
2. Instala `sharp` para Linux:
```
   cd lambdas/crop
   npm install --os=linux --cpu=x64 --libc=glibc sharp@0.33.5
   cd ../..
```
3. Inicializa y crea los workspaces:
```
   terraform init
   terraform workspace new dev
   terraform workspace new qa
   terraform workspace new prod
```
4. Despliega un entorno:
```
   terraform workspace select dev
   terraform apply -var-file=envs/dev.tfvars
```
   Opcional: `-var="alert_email=tu@correo.com"` para recibir alertas por gmail.
5. Prueba:
```
   terraform output upload_url
   curl -i -X POST -H "Content-Type: image/png" --data-binary "@foto.png" URL
```
6. Destruye: `terraform destroy -var-file=envs/dev.tfvars`.

## Cambios respecto al diagrama
- Región us-east-2, no la us-east-1.
- Sin VPC, NAT Gateways ni endpoint de SQS: las Lambdas solo hablan con S3 y SQS, que son servicios de AWS. Evita costos por hora de los NAT e interface endpoints.
- Límite de imagen 4 MB: API Gateway + Lambda aceptan 6 MB de payload.
- Imagen enviada como cuerpo binario directo, no multipart.
- Throttling de API bajado a 100/200 rps.
- `force_destroy = true` en S3 y log groups creados en Terraform para que el destroy no deje huérfanos.
- Una sola crop-lambda y una sola upload-lambda.