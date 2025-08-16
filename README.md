### Container image build for containerized container image builder

https://github.com/chainguard-dev/kaniko

Currently able to build the debug image on Kaniko using a hack to move the kaniko working directory to /kaniko-build before running executor.

Current issues:
- `/kaniko/.docker` is not created
- `/kaniko` permission is not 777