# =============================================================================
# Graph testbed image: the Graph engine plus its demo use cases and seeded data, in namespace TESTBED.
# Demo cases: Logistics risk tracing, EMR contact tracing, curated genome Circos. Seeded data: Persian Gulf risk case, 2000-person contact tracing.
# Not included on purpose: ClinicalResearch.ClinicalAI.*, ProjectKB.*, the EMR/drug/gene sample, the PGx platform and GraphAction.
#
# Build (normally through container/docker-compose.yml; the build context is the repository root):
#   docker build -f container/Dockerfile -t graph-testbed:latest .
# Base image: any InterSystems IRIS or IRIS for Health image with vector support (2025.1 or newer).
#   docker build -f container/Dockerfile --build-arg IMAGE=<your image> -t graph-testbed:latest .
# The build context is whitelisted by container/Dockerfile.dockerignore.
# =============================================================================
ARG IMAGE=containers.intersystems.com/intersystems/iris-community:latest-cd
FROM ${IMAGE}

USER root
RUN mkdir -p /opt/testbed && chown -R ${ISC_PACKAGE_MGRUSER}:${ISC_PACKAGE_IRISGROUP} /opt/testbed
USER ${ISC_PACKAGE_MGRUSER}

# Sources: the Graph package from the workspace, plus the classes that exist only in the TESTBED instance (Logistics, EMR contact tracing, genome demo)
COPY --chown=${ISC_PACKAGE_MGRUSER}:${ISC_PACKAGE_IRISGROUP} src/Graph /opt/testbed/src/Graph
COPY --chown=${ISC_PACKAGE_MGRUSER}:${ISC_PACKAGE_IRISGROUP} DemoContainer/classes/ /opt/testbed/src/
COPY --chown=${ISC_PACKAGE_MGRUSER}:${ISC_PACKAGE_IRISGROUP} DemoContainer/Install/Testbed.cls /opt/testbed/src/Install/

COPY --chown=${ISC_PACKAGE_MGRUSER}:${ISC_PACKAGE_IRISGROUP} DemoContainer/iris.testbed.script DemoContainer/iris.finish.script DemoContainer/post-start.sh /opt/testbed/

RUN chmod 755 /opt/testbed/post-start.sh

# Build time: start the instance, create TESTBED, load/compile, seed, self-check, stop.
# Each session exits non-zero on failure, which fails the build.
RUN iris start IRIS \
    && iris session IRIS < /opt/testbed/iris.testbed.script \
    && iris session IRIS -U TESTBED < /opt/testbed/iris.finish.script \
    && iris stop IRIS quietly

EXPOSE 1972 52773
