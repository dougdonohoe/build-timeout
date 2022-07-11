# Build Timeout

* Filed under [buildx issue #1205](https://github.com/docker/buildx/issues/1205)

## Introduction

Multi-architecture images are becoming more desirable with the advent of the Apple M1 laptops.
However, building multi-architecture images (e.g., `arm64` and `amd64`) in GCP Cloud Build can take a long time due 
to the need to use QEMU emulation for the non-`amd64` architectures.  A 15-minute build in `amd64` can take 5x longer
under emulation for `arm64`.  Builds that take over an hour fail during the push step at the end.  This repository 
demonstrates the problem by using `sleep` to emulate a long build.

There is a work-around that hints at the source of the problem.  It seems that the `buildx` builder
is allocating oauth tokens when it starts up, and those have an hour expiration (at least on GCP Cloud Build).  The
work-around restarts the builder before doing push actions (see below for full details).

Running the same build locally (i.e., **NOT** in Cloud Build) works fine (see example at bottom of this page).

## Error

Long-running `docker buildx` builds in GCP Cloud Build timeout with this error when pushing at end of build:

```text
Step #2 - "long-build":  > exporting to image:
Step #2 - "long-build": ------
Step #2 - "long-build": error: failed to solve: failed to fetch oauth token: unexpected status: 401 Unauthorized
Step #2 - "long-build": make: *** [Makefile:229: buildx-publish-runtime-sleep] Error 1
```

## Version

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

## Prerequisites

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
and are pointing at your project.  You should have done something roughly like this:

```shell
gcloud auth login
gcloud auth configure-docker gcr.io,us-central1-docker.pkg.dev
gcloud config set project my-project
```

## Setup

Our base image is a multi-arch Alpine image, which is used to create our testing image and the cloud builder image.

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

The output looks like this:

```text
Step #1 - "long-build": #17 3674.0 Slept 3660 seconds of 61 minutes #732/732...
Step #1 - "long-build": #17 3674.0 Done sleeping 61 minutes.
Step #1 - "long-build": #17 DONE 3674.0s
Step #1 - "long-build":
Step #1 - "long-build": #18 exporting to image
Step #1 - "long-build": #18 exporting layers
Step #1 - "long-build": #18 exporting layers 0.5s done
Step #1 - "long-build": #18 exporting manifest sha256:477a69c762738fc8c3a661740c03abb8dc7613198f002d0dba9b8e7b896aa95e 0.0s done
Step #1 - "long-build": #18 exporting config sha256:f748fda9559410325362f46688548be8011bb9140f38c79535bea4a12a769d1e
Step #1 - "long-build": #18 exporting config sha256:f748fda9559410325362f46688548be8011bb9140f38c79535bea4a12a769d1e done
Step #1 - "long-build": #18 exporting manifest sha256:1ece3dce6c9d81e54ec5372f95dd662eba5e1f0e2a3fd087d75b2c15155a1a44 0.0s done
Step #1 - "long-build": #18 exporting config sha256:fac94e796bb4fbc5097900438f06ceba09d1b11d06a46837cd9d5b47201f0911 done
Step #1 - "long-build": #18 exporting manifest list sha256:ebb9b22139ae120c3c9835d3e860b72a7a7a658e9a2c261d059a9e0de12630f9 0.0s done
Step #1 - "long-build": #18 pushing layers
Step #1 - "long-build": #18 pushing layers 0.1s done
Step #1 - "long-build": #18 ERROR: failed to authorize: failed to fetch oauth token: unexpected status: 401 Unauthorized
Step #1 - "long-build":
Step #1 - "long-build": #19 [auth] my-project/slow-build-test/build/slow-build:pull,push token for us-central1-docker.pkg.dev
Step #1 - "long-build": #19 DONE 0.0s
Step #1 - "long-build":
Step #1 - "long-build": #20 [auth] my-project/slow-build-test/build/slow-build:pull,push token for us-central1-docker.pkg.dev
Step #1 - "long-build": #20 DONE 0.0s
Step #1 - "long-build": ------
Step #1 - "long-build":  > importing cache manifest from us-central1-docker.pkg.dev/my-project/slow-build-test/cache/build/slow-build:4-sleep:
Step #1 - "long-build": ------
Step #1 - "long-build": ------
Step #1 - "long-build":  > exporting to image:
Step #1 - "long-build": ------
Step #1 - "long-build": error: failed to solve: failed to fetch oauth token: unexpected status: 401 Unauthorized
Step #1 - "long-build": make: *** [Makefile:75: buildx-publish-runtime-sleep] Error 1
Finished Step #1 - "long-build"
```

To show it is in fact an hour timeout, try running with less than an hour:

```shell
MINUTES=58 make cloud-build-timeout
```

It succeeds:

```text
Step #1 - "long-build": #17 3493.6 Slept 3480 seconds of 58 minutes #696/696...
Step #1 - "long-build": #17 3493.6 Done sleeping 58 minutes.
Step #1 - "long-build": #17 DONE 3493.6s
Step #1 - "long-build":
Step #1 - "long-build": #18 exporting to image
Step #1 - "long-build": #18 exporting layers
Step #1 - "long-build": #18 exporting layers 0.5s done
Step #1 - "long-build": #18 exporting manifest sha256:6579a74962d53cf8e4ac609c9716b9baacfd55f906d77402528b7703bbb5e5e6 0.0s done
Step #1 - "long-build": #18 exporting config sha256:8a11c7f83a1dfda9a9c384a0cd50f1ffb3863629ce277a6e34a21986e4174f93 0.0s done
Step #1 - "long-build": #18 exporting manifest sha256:6e26f0bab911f0b7b90e9876d8319cf91fd47f1a83a7a43c857fcea18eec1443 0.0s done
Step #1 - "long-build": #18 exporting config sha256:3f91f2711a5947d141b21eeb710c66b2b4e30c8cd80266b9fc6b4e45d2d39f8d
Step #1 - "long-build": #18 exporting config sha256:3f91f2711a5947d141b21eeb710c66b2b4e30c8cd80266b9fc6b4e45d2d39f8d 0.0s done
Step #1 - "long-build": #18 exporting manifest list sha256:f9868273a5375a6ff9df43f4507a884199483830b9c879d920d0e4dc6671cc37 0.0s done
Step #1 - "long-build": #18 pushing layers
Step #1 - "long-build": #18 ...
Step #1 - "long-build":
Step #1 - "long-build": #19 [auth] product360-ops/doug-test/build/slow-build:pull,push token for us-central1-docker.pkg.dev
Step #1 - "long-build": #19 DONE 0.0s
Step #1 - "long-build":
Step #1 - "long-build": #18 exporting to image
Step #1 - "long-build": #18 pushing layers 2.6s done
Step #1 - "long-build": #18 pushing manifest for us-central1-docker.pkg.dev/product360-ops/doug-test/build/slow-build:4-sleep@sha256:f9868273a5375a6ff9df43f4507a884199483830b9c879d920d0e4dc6671cc37
Step #1 - "long-build": #18 pushing manifest for us-central1-docker.pkg.dev/product360-ops/doug-test/build/slow-build:4-sleep@sha256:f9868273a5375a6ff9df43f4507a884199483830b9c879d920d0e4dc6671cc37 0.7s done
Step #1 - "long-build": #18 DONE 3.9s
Step #1 - "long-build":
Step #1 - "long-build": #20 exporting cache
Step #1 - "long-build": #20 preparing build cache for export 0.0s done
Step #1 - "long-build": #20 writing layer sha256:1c66f413db7fbc097e3e2033d41f81e665aa88919ec7bc591ae919aab3442fe9
Step #1 - "long-build": #20 ...
Step #1 - "long-build":
Step #1 - "long-build": #21 [auth] product360-ops/doug-test/cache/build/slow-build:pull,push token for us-central1-docker.pkg.dev
Step #1 - "long-build": #21 DONE 0.0s
Step #1 - "long-build":
Step #1 - "long-build": #20 exporting cache
Step #1 - "long-build": #20 writing layer sha256:1c66f413db7fbc097e3e2033d41f81e665aa88919ec7bc591ae919aab3442fe9 0.5s done
Step #1 - "long-build": #20 writing layer sha256:4160402faa60110e9d12f70fc1588f0de6d5a6b67fc3c7d975bfab2bab65cc32
[snip]
Step #1 - "long-build": #20 writing manifest sha256:310a748fffdac1f5bdb4c6d8a34a6095fd031c0b553b4568c492ea8174d28ece
Step #1 - "long-build": #20 writing manifest sha256:310a748fffdac1f5bdb4c6d8a34a6095fd031c0b553b4568c492ea8174d28ece 0.1s done
Step #1 - "long-build": #20 DONE 2.1s
Step #1 - "long-build": ------
Step #1 - "long-build":  > importing cache manifest from us-central1-docker.pkg.dev/product360-ops/doug-test/cache/build/slow-build:4-sleep:
Step #1 - "long-build": ------
Finished Step #1 - "long-build"
```
## Workaround

There is a work-around which boils down to:

1. Build without `--push` or `--cache-to`
2. Stop buildx builder
3. Build normally

Why this appears to work (my guess) is that the builder allocates a token when it is started, and it eventually
times out.  Doing the first (long) build caches the results locally allowing the second build (with a new
builder) to push cache and final images w/out running into the timeout.

```shell
make cloud-build-workaround
```

**NOTE**: You can run the work-around build concurrently to the problematic build (this is helpful since it takes
an hour to reproduce the problem).

The output looks like this:

```text
Step #1 - "long-build": #17 3672.9 Slept 3660 seconds of 61 minutes #732/732...
Step #1 - "long-build": #17 3672.9 Done sleeping 61 minutes.
Step #1 - "long-build": #17 DONE 3672.9s
Step #1 - "long-build": ------
Step #1 - "long-build":  > importing cache manifest from us-central1-docker.pkg.dev/my-project/slow-build-test/cache/build/slow-build:4-sleep-workaround:
[snip]
Step #1 - "long-build": DOCKER_BUILDKIT=1 docker buildx stop builder-local # <--- key to the whole workaround
[snip]
Step #1 - "long-build": #17 [linux/arm64 4/4] RUN /usr/local/bin/sleep.sh 61
Step #1 - "long-build": #17 CACHED
Step #1 - "long-build":
Step #1 - "long-build": #18 exporting to image
Step #1 - "long-build": #18 exporting layers
Step #1 - "long-build": #18 exporting layers 0.4s done
Step #1 - "long-build": #18 exporting manifest sha256:1195febe0ef97ace6af7e897416d5e39fdc77c7167840e772ba58218e7538b9e 0.0s done
Step #1 - "long-build": #18 exporting config sha256:c1d2bf59e1a736cb0adf9cc02e25197ada2c0c414fb07ec12ee724e0962fe0b5 done
Step #1 - "long-build": #18 exporting manifest sha256:8ebfa1cf319516d0aa534dde1492b2d6b4fee9876f66086834656dcbbe193610 0.0s done
Step #1 - "long-build": #18 exporting config sha256:bdbe28ba7f93daeb88cc2558a6fc88464b7dc2e72545fb04d49fd47d75a93eac done
Step #1 - "long-build": #18 exporting manifest list sha256:94b313aee4a3e9b1b634911ecfafe6d6ac13593820b25b937c79837d8f272657 0.0s done
Step #1 - "long-build": #18 pushing layers
Step #1 - "long-build": #18 ...
Step #1 - "long-build":
Step #1 - "long-build": #19 [auth] my-project/slow-build-test/build/slow-build:pull,push token for us-central1-docker.pkg.dev
Step #1 - "long-build": #19 DONE 0.0s
Step #1 - "long-build":
Step #1 - "long-build": #18 exporting to image
Step #1 - "long-build": #18 pushing layers 5.0s done
Step #1 - "long-build": #18 pushing manifest for us-central1-docker.pkg.dev/my-project/slow-build-test/build/slow-build:4-sleep-workaround@sha256:94b313aee4a3e9b1b634911ecfafe6d6ac13593820b25b937c79837d8f272657
Step #1 - "long-build": #18 pushing manifest for us-central1-docker.pkg.dev/my-project/slow-build-test/build/slow-build:4-sleep-workaround@sha256:94b313aee4a3e9b1b634911ecfafe6d6ac13593820b25b937c79837d8f272657 0.7s done
Step #1 - "long-build": #18 DONE 6.1s
Step #1 - "long-build":
Step #1 - "long-build": #20 exporting cache
Step #1 - "long-build": #20 preparing build cache for export 0.0s done
Step #1 - "long-build": #20 writing layer sha256:0d4b37deb72fe85333d70f16727ad80904db5c3f830b8fe1b73730e821489856
Step #1 - "long-build": #20 ...
Step #1 - "long-build":
Step #1 - "long-build": #21 [auth] my-project/slow-build-test/cache/build/slow-build:pull,push token for us-central1-docker.pkg.dev
Step #1 - "long-build": #21 DONE 0.0s
Step #1 - "long-build":
Step #1 - "long-build": #20 exporting cache
Step #1 - "long-build": #20 writing layer sha256:0d4b37deb72fe85333d70f16727ad80904db5c3f830b8fe1b73730e821489856 0.7s done
Step #1 - "long-build": #20 writing layer sha256:3fe385f9a00ea5bd5de3878d11e56ef1e070cc4a7ec0259f0708c33a5f42d018
[snip]
Step #1 - "long-build": #20 writing manifest sha256:b30984bc31fa13d5bbb3951c2ad3abd23b11a6630dbc864c40587680e4f96014
Step #1 - "long-build": #20 writing manifest sha256:b30984bc31fa13d5bbb3951c2ad3abd23b11a6630dbc864c40587680e4f96014 0.2s done
Step #1 - "long-build": #20 DONE 3.5s
Step #1 - "long-build": ------
Step #1 - "long-build":  > importing cache manifest from us-central1-docker.pkg.dev/my-project/slow-build-test/cache/build/slow-build:4-sleep-workaround:
Step #1 - "long-build": ------
Finished Step #1 - "long-build"
```

**NOTE**:  Running the work-around a second time should not take an hour since it should take advantage of the 
`--cache-to`/`--cache-from` directives.  To re-run with the sleep, delete the `my-project/slow-build-test/cache/build/slow-build` 
folder in artifact registry.

## Local Build

To run the `docker buildx` step locally and show this way does not timeout:

```shell
make buildx-publish-runtime-sleep
```

The output looks like this:

```text
#14 3681.5 Slept 3660 seconds of 61 minutes #732/732...
#14 3681.5 Done sleeping 61 minutes.
#14 DONE 3681.6s

#15 exporting to image
#15 exporting layers
#15 exporting layers 0.3s done
#15 exporting manifest sha256:f166a63fff7b3f3cea43e29892b7c2836da08d619b572b692959b6daff0468d8 done
#15 exporting config sha256:a056c68734822973a63d7652c4757a307818e95416edf6a6a719d5d852353882 done
#15 exporting manifest sha256:a65147974eb64a0d370f10327ad227bd94707645f6d07b0aa71e1aa444f12916 done
#15 exporting config sha256:0e4f5794f154abe3886dde3078ee347b5e426b883dcdfdf0923fe682ea9d4880 0.0s done
#15 exporting manifest list sha256:b150e5c9e611cb6e71e41d97ed23743a308a0b67a417cdf2e3344c4b77a49e03 done
#15 pushing layers
#15 ...

#16 [auth] my-project/slow-build-test/build/slow-build:pull,push token for us-central1-docker.pkg.dev
#16 DONE 0.0s

#15 exporting to image
#15 pushing layers 3.3s done
#15 pushing manifest for us-central1-docker.pkg.dev/my-project/slow-build-test/build/slow-build:4-sleep@sha256:b150e5c9e611cb6e71e41d97ed23743a308a0b67a417cdf2e3344c4b77a49e03
#15 pushing manifest for us-central1-docker.pkg.dev/my-project/slow-build-test/build/slow-build:4-sleep@sha256:b150e5c9e611cb6e71e41d97ed23743a308a0b67a417cdf2e3344c4b77a49e03 0.6s done
#15 DONE 4.3s

#17 exporting cache
#17 preparing build cache for export 0.0s done
#17 writing layer sha256:047ea9f42a46b3a780c0a0b7536c97f2de82cfa9e2f2798443b659b07b432790
#17 ...

#18 [auth] my-project/slow-build-test/cache/build/slow-build:pull,push token for us-central1-docker.pkg.dev
#18 DONE 0.0s

#17 exporting cache
#17 writing layer sha256:047ea9f42a46b3a780c0a0b7536c97f2de82cfa9e2f2798443b659b07b432790 1.3s done
#17 writing layer sha256:4f4fb700ef54461cfa02571ae0db9a0dc1e0cdb5577484a6d75e68dc38e8acc1 done
[snip]
#17 writing manifest sha256:a5e1be9e05351460de5eeda60fe0d2fd185e8363d8ef60c404d1fa1fe4c7a476
#17 writing manifest sha256:a5e1be9e05351460de5eeda60fe0d2fd185e8363d8ef60c404d1fa1fe4c7a476 0.2s done
#17 DONE 2.4s
------
 > importing cache manifest from us-central1-docker.pkg.dev/my-project/slow-build-test/cache/build/slow-build:4-sleep:
------
```
