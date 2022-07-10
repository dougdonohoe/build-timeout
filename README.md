# Build Timeout

## Introduction

Multi-architecture images are becoming more desirable with the advent of the Apple M1 laptops.
However, building multi-architecture images (e.g., `arm64` and `amd64`) in GCP Cloud Build can take a long time due 
to the need to use QEMU emulation for the non-`amd64` architectures.  Builds that take over an hour fail during the
push step at the end.  This repository demonstrates the problem using `sleep` in the build step.

There is a work-around, described below, that hints at the source of the problem.  It seems that the `buildx` builder
is allocating tokens when it starts up, and those have an hour expiration (at least on GCP Cloud Build).  The
work-around restarts the builder before doing push actions.

## Error

Long-running `docker buildx` builds in GCP Cloud Build timeout with this error when pushing at end of build:

```text
Step #2 - "long-build": #17 3669.2 Sleep 5 #732/732...
Step #2 - "long-build": #17 DONE 3674.2s
Step #2 - "long-build": 
Step #2 - "long-build": #18 exporting to image
Step #2 - "long-build": #18 exporting layers
Step #2 - "long-build": #18 exporting layers 0.6s done
Step #2 - "long-build": #18 exporting manifest sha256:e8b757e6a3e5d2944100667911a2aa9de6989371df282ed6d236b195142047a0 0.0s done
Step #2 - "long-build": #18 exporting config sha256:2fa91bfb974e5553ec801475d2c4e33bb07e58f628ad41f405e7a698a8efbe0d done
Step #2 - "long-build": #18 exporting manifest sha256:cd8adf4ae775ea933f415a72c90f3360d84e86d0e7a190db68a36555c7a95d26 0.0s done
Step #2 - "long-build": #18 exporting config sha256:5e79f409c7bb3241f562488b83af9a049f961fec7e7311656a1617410bfd7f37 done
Step #2 - "long-build": #18 exporting manifest list sha256:0924c2ae8a99c295a87d8968be40bba415968f04760652e0152d5378eecfad92 0.0s done
Step #2 - "long-build": #18 pushing layers
Step #2 - "long-build": #18 ...
Step #2 - "long-build": 
Step #2 - "long-build": #19 [auth] my-project/slow-build-test/build/slow-build:pull,push token for us-central1-docker.pkg.dev
Step #2 - "long-build": #19 DONE 0.0s
Step #2 - "long-build": 
Step #2 - "long-build": #20 [auth] my-project/slow-build-test/build/slow-build:pull,push token for us-central1-docker.pkg.dev
Step #2 - "long-build": #20 DONE 0.0s
Step #2 - "long-build": 
Step #2 - "long-build": #18 exporting to image
Step #2 - "long-build": #18 pushing layers 0.9s done
Step #2 - "long-build": #18 ERROR: failed to authorize: failed to fetch oauth token: unexpected status: 401 Unauthorized
Step #2 - "long-build": 
Step #2 - "long-build": #21 [auth] my-project/slow-build-test/build/slow-build:pull,push token for us-central1-docker.pkg.dev
Step #2 - "long-build": #21 DONE 0.0s
Step #2 - "long-build": ------
Step #2 - "long-build":  > importing cache manifest from us-central1-docker.pkg.dev/my-project/slow-build-test/cache/build/slow-build:4-sleep:
Step #2 - "long-build": ------
Step #2 - "long-build": ------
Step #2 - "long-build":  > exporting to image:
Step #2 - "long-build": ------
Step #2 - "long-build": error: failed to solve: failed to fetch oauth token: unexpected status: 401 Unauthorized
Step #2 - "long-build": make: *** [Makefile:229: buildx-publish-runtime-sleep] Error 1
```

**NOTE**:  Running same build locally (i.e., NOT in Cloud Build) works fine (see example at bottom of this page).

The version of all things Docker is printed in the `setup` step:

```text
Step #0 - "setup": Client:
Step #0 - "setup":  Version:           20.10.16
Step #0 - "setup":  API version:       1.41
Step #0 - "setup":  Go version:        go1.17.10
Step #0 - "setup":  Git commit:        aa7e414fdcb23a66e8fabbef0a560ef1769eace5
Step #0 - "setup":  Built:             Sun May 15 15:07:52 2022
Step #0 - "setup":  OS/Arch:           linux/amd64
Step #0 - "setup":  Context:           default
Step #0 - "setup":  Experimental:      true
Step #0 - "setup": 
Step #0 - "setup": Server: Docker Engine - Community
Step #0 - "setup":  Engine:
Step #0 - "setup":   Version:          20.10.17
Step #0 - "setup":   API version:      1.41 (minimum version 1.12)
Step #0 - "setup":   Go version:       go1.17.11
Step #0 - "setup":   Git commit:       a89b842
Step #0 - "setup":   Built:            Mon Jun  6 23:01:23 2022
Step #0 - "setup":   OS/Arch:          linux/amd64
Step #0 - "setup":   Experimental:     false
Step #0 - "setup":  containerd:
Step #0 - "setup":   Version:          1.6.6
Step #0 - "setup":   GitCommit:        10c12954828e7c7c9b6e0ea9b0c02b01407d3ae1
Step #0 - "setup":  runc:
Step #0 - "setup":   Version:          1.1.2
Step #0 - "setup":   GitCommit:        v1.1.2-0-ga916309
Step #0 - "setup":  docker-init:
Step #0 - "setup":   Version:          0.19.0
Step #0 - "setup":   GitCommit:        de40ad0
Step #0 - "setup": github.com/docker/buildx v0.8.2 6224def4dd2c3d347eee19db595348c50d7cb491
```

## Prerequisite

You first need a GCP artifact registry and repository - edit the top of the Makefile to define them.

```makefile
GCP_PROJECT ?= my-project
REPO ?= slow-build-test
ARTIFACT_REGISTRY ?= us-central1-docker.pkg.dev/$(GCP_PROJECT)
```

Or alternatively prefix any make commands seen below:

```shell
GCP_PROJECT=my-project REPO=my-repo make ...
```

The steps below use `gcloud`, and we assume you have it installed, configured Docker to use it, 
and are pointing at your project.  Roughly something like this:

```shell
gcloud auth login
gcloud auth configure-docker gcr.io,us-central1-docker.pkg.dev
gcloud config set project my-project
```

## Setup

Our base image is a multi-arch Alpine image, which is used to create our image and the cloud builder image.

Run these commands to copy the thirdparty image to your artifact registry and create the `docker buildx` cloud builder:

```shell
make thirdparty
make build-publish-cloud-builder
```

## Cloud Build

To reproduce the error, start a cloud build, wait an hour and boom.

```shell
make cloud-build-timeout
```

The output is shown above in the Error section.

## Workaround

There is a work-around which boils down to:

1. Build without `--push` or `--cache-co`
2. Stop buildx builder
3. Build normally

Why this appears to work (my guess) is that the builder allocates a token when it is started, and it eventually
times out.  Doing the first (long) build caches the results locally allowing the second build (with a new
builder) to push cache and final images w/out running into the timeout.

```shell
make cloud-build-workaround
```

**NOTE**: You can run the work-around build concurrently to the problematic build.

The output looks like this:

```text
Step #1 - "long-build": #17 3668.1 Sleep 5 #732/732...
Step #1 - "long-build": #17 DONE 3673.1s
Step #1 - "long-build": ------
Step #1 - "long-build":  > importing cache manifest from us-central1-docker.pkg.dev/my-project/slow-build-test/cache/build/slow-build:4-sleep-wor
[snip]
Step #1 - "long-build": #17 [linux/amd64 4/4] RUN /usr/local/bin/sleep.sh
Step #1 - "long-build": #17 CACHED
Step #1 - "long-build":
Step #1 - "long-build": #18 exporting to image
Step #1 - "long-build": #18 exporting layers
Step #1 - "long-build": #18 exporting layers 0.5s done
Step #1 - "long-build": #18 exporting manifest sha256:78af7f94753d44b5bc1aeb68de830a1b76714ef2cdbebe857a8e23819cb5d79f 0.0s done
Step #1 - "long-build": #18 exporting config sha256:6ccd03dd6b430835039084c84a0353f04bebac5144263767d4d786966b6737df done
Step #1 - "long-build": #18 exporting manifest sha256:eafc81bb721d213228d841333d75dfa9a306e794bacc1066dfd2efc7acf9589a 0.0s done
Step #1 - "long-build": #18 exporting config sha256:55e0d151d88f9edf75f650740207ede210aa215843f2ee8eee42560d0369038e done
Step #1 - "long-build": #18 exporting manifest list sha256:4e7e1ec6a8d1fc95e788510f64246f74e9072cd3a53ddef0b6f7be2f1990cfa1 0.0s done
Step #1 - "long-build": #18 pushing layers
Step #1 - "long-build": #18 ...
Step #1 - "long-build":
Step #1 - "long-build": #19 [auth] my-project/slow-build-test/build/slow-build:pull,push token for us-central1-docker.pkg.dev
Step #1 - "long-build": #19 DONE 0.0s
Step #1 - "long-build":
Step #1 - "long-build": #18 exporting to image
Step #1 - "long-build": #18 pushing layers 0.8s done
Step #1 - "long-build": #18 pushing manifest for us-central1-docker.pkg.dev/my-project/slow-build-test/build/slow-build:4-sleep-workaround@sha256:4e7e1ec6a8d1fc95e788510f64246f74e9072cd3a53ddef0b6f7be2f1990cfa1
Step #1 - "long-build": #18 pushing manifest for us-central1-docker.pkg.dev/my-project/slow-build-test/build/slow-build:4-sleep-workaround@sha256:4e7e1ec6a8d1fc95e788510f64246f74e9072cd3a53ddef0b6f7be2f1990cfa1 0.3s done
Step #1 - "long-build": #18 DONE 1.6s
Step #1 - "long-build":
Step #1 - "long-build": #20 exporting cache
Step #1 - "long-build": #20 preparing build cache for export 0.0s done
Step #1 - "long-build": #20 writing layer sha256:02a8f72729a212553ae864a43f79f67d7e6771414ea8940fa729723e562664f6
Step #1 - "long-build": #20 ...
Step #1 - "long-build":
Step #1 - "long-build": #21 [auth] my-project/slow-build-test/cache/build/slow-build:pull,push token for us-central1-docker.pkg.dev
Step #1 - "long-build": #21 DONE 0.0s
Step #1 - "long-build":
Step #1 - "long-build": #20 exporting cache
Step #1 - "long-build": #20 writing layer sha256:02a8f72729a212553ae864a43f79f67d7e6771414ea8940fa729723e562664f6 0.1s done
Step #1 - "long-build": #20 writing layer sha256:0978988867c285cec7a54a96b3379b2ffd930f0186db3e72837d643216969a41 0.0s done
Step #1 - "long-build": #20 writing layer sha256:0aefa9e718296793f3e9fc420e61842baec3d3e7d8c0749e9334d66f5b79f7e5
Step #1 - "long-build": #20 writing layer sha256:0aefa9e718296793f3e9fc420e61842baec3d3e7d8c0749e9334d66f5b79f7e5 0.0s done
Step #1 - "long-build": #20 writing layer sha256:4f4fb700ef54461cfa02571ae0db9a0dc1e0cdb5577484a6d75e68dc38e8acc1 done
Step #1 - "long-build": #20 writing layer sha256:86b80458730eaed01aced9bd7e2c4a236e40bd20144dcc501c35f113166b10e4 0.0s done
Step #1 - "long-build": #20 writing layer sha256:9981e73032c8833e387a8f96986e560edbed12c38119e0edb0439c9c2234eac9 0.0s done
Step #1 - "long-build": #20 writing layer sha256:df9b9388f04ad6279a7410b85cedfdcb2208c0a003da7ab5613af71079148139
Step #1 - "long-build": #20 writing layer sha256:df9b9388f04ad6279a7410b85cedfdcb2208c0a003da7ab5613af71079148139 0.0s done
Step #1 - "long-build": #20 writing config sha256:85fed0ae6745088570cda8be315ebf18361197b297d7132aef481857d0ff0503
Step #1 - "long-build": #20 writing config sha256:85fed0ae6745088570cda8be315ebf18361197b297d7132aef481857d0ff0503 0.2s done
Step #1 - "long-build": #20 writing manifest sha256:935915b88030081af4b5d8b6307f83c79951dc55120e022ad1d10140e5549072 0.0s done
Step #1 - "long-build": #20 DONE 0.6s
Step #1 - "long-build": ------
Step #1 - "long-build":  > importing cache manifest from us-central1-docker.pkg.dev/my-project/slow-build-test/cache/build/slow-build:4-sleep-workaround:
Step #1 - "long-build": ------
```

**NOTE**:  Running the work-around a second time should not take an hour since it should take advantage of the 
`--cache-to`/`--cache-from` directives.  To re-run, delete the `my-project/slow-build-test/cache/build/slow-build` 
folder in artifact registry.

## Local Build

To run the `docker buildx` step locally (which does not timeout):

```shell
make buildx-publish-runtime-sleep
```

The output looks like this:

```text
#15 3675.8 Sleep 5 #732/732...
#15 DONE 3680.8s

#16 exporting to image
#16 exporting layers
#16 exporting layers 0.3s done
#16 exporting manifest sha256:70d5e82a55f04e6f6aab0ffaee1cad335dda6c2611b620638aa96784f01e355f done
#16 exporting config sha256:5ae0062f3f133702dede2bb4f0cf6963b9fe34de3a943b5a88da736a6997c667 done
#16 exporting manifest sha256:b1984fbdd72f90b627efa44ebcba5963b87e74bf0e81c92811be6a8391ad9f4c 0.0s done
#16 exporting config sha256:9577e589d2e608356cd4c801e169dc04846f097ec4d9fa81177a0a2ebda86bd9 done
#16 exporting manifest list sha256:cf244fcc82a6f16f4e425087cc27553bbd88be1b0d3c18c3260fbb51339d6915 done
#16 pushing layers
#16 ...

#17 [auth] my-project/slow-build-test/build/slow-build:pull,push token for us-central1-docker.pkg.dev
#17 DONE 0.0s

#16 exporting to image
#16 pushing layers 3.1s done
#16 pushing manifest for us-central1-docker.pkg.dev/my-project/slow-build-test/build/slow-build:4-sleep@sha256:cf244fcc82a6f16f4e425087cc27553bbd88be1b0d3c18c3260fbb51339d6915
#16 pushing manifest for us-central1-docker.pkg.dev/my-project/slow-build-test/build/slow-build:4-sleep@sha256:cf244fcc82a6f16f4e425087cc27553bbd88be1b0d3c18c3260fbb51339d6915 0.6s done
#16 DONE 4.1s

#18 exporting cache
#18 preparing build cache for export 0.0s done
#18 writing layer sha256:0700eccdbdd085a5bd215241380e5a802365acb37dd4ac7665b48f7d9446b0cd
#18 ...

#19 [auth] my-project/slow-build-test/cache/build/slow-build:pull,push token for us-central1-docker.pkg.dev
#19 DONE 0.0s

#18 exporting cache
#18 writing layer sha256:0700eccdbdd085a5bd215241380e5a802365acb37dd4ac7665b48f7d9446b0cd 1.4s done
#18 writing layer sha256:25a03cc8c33355bf6116aef736362d27778a4bfdf78c335f059c937154c576c4
#18 writing layer sha256:25a03cc8c33355bf6116aef736362d27778a4bfdf78c335f059c937154c576c4 0.1s done
#18 writing layer sha256:4f4fb700ef54461cfa02571ae0db9a0dc1e0cdb5577484a6d75e68dc38e8acc1 done
#18 writing layer sha256:9590aaa1e6776aef2f6730a2500960ad54c4f16af00f30c40969135ccfd4e668
#18 writing layer sha256:9590aaa1e6776aef2f6730a2500960ad54c4f16af00f30c40969135ccfd4e668 0.1s done
#18 writing layer sha256:9981e73032c8833e387a8f96986e560edbed12c38119e0edb0439c9c2234eac9 0.1s done
#18 writing layer sha256:d5bc1dbf903bead4307bfc36f71af369f91e48f967087fe087753ea0f33d540d
#18 writing layer sha256:d5bc1dbf903bead4307bfc36f71af369f91e48f967087fe087753ea0f33d540d 0.1s done
#18 writing layer sha256:df9b9388f04ad6279a7410b85cedfdcb2208c0a003da7ab5613af71079148139 0.1s done
#18 writing config sha256:d1793b6a18b3447ecf66d0842b8bc1716d4a37113754dc648e900a570c15335f
#18 writing config sha256:d1793b6a18b3447ecf66d0842b8bc1716d4a37113754dc648e900a570c15335f 0.4s done
#18 writing manifest sha256:a8cd72e735710de89db81c678206bf523e555ede40d8a33cb59fb54579c97055
#18 writing manifest sha256:a8cd72e735710de89db81c678206bf523e555ede40d8a33cb59fb54579c97055 0.1s done
#18 DONE 2.5s
------
 > importing cache manifest from us-central1-docker.pkg.dev/my-project/slow-build-test/cache/build/slow-build:4-sleep:
------
```
