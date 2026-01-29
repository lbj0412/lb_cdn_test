# lb_cdn_test

간단한 설명
- 이 레포지토리는 Google Cloud CDN과 비공개 GCS(origin)를 다루는 Terraform 예제 구성입니다.

빠른 시작
- 필수: `gcloud` CLI, Terraform (>=1.x), GCP 프로젝트 및 적절한 권한
- 현재 브랜치에서 작업 중이면 `.terraform` 디렉터리가 워킹 디렉터리에 남아 있을 수 있습니다. 원격에 푸시하기 전에 추적 대상에서 제거하세요:

```bash
rm -rf .terraform
git rm -r --cached .terraform || true
git add .gitignore README.md
git commit -m "Remove .terraform from tracking and add README"
```

Terraform 사용 예

```bash
terraform init
terraform plan -out=tfplan
terraform apply tfplan
terraform destroy
```


참고 자료
- 구현 참고: Private GCS origin을 통한 Cloud CDN 구성 관련 글 — https://medium.com/@thetechbytes/private-gcs-bucket-access-through-google-cloud-cdn-430d940ebad9
