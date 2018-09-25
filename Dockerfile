FROM rocker/verse:3.4.3
USER root

ENV NB_USER rstudio
ENV NB_UID 1000
ENV VENV_DIR /srv/venv

# Set ENV for all programs...
ENV PATH ${VENV_DIR}/bin:$PATH
# And set ENV for R! It doesn't read from the environment...
RUN echo "PATH=${PATH}" >> /usr/local/lib/R/etc/Renviron

# The `rsession` binary that is called by nbrsessionproxy to start R doesn't seem to start
# without this being explicitly set
ENV LD_LIBRARY_PATH /usr/local/lib/R/lib

ENV HOME /home/${NB_USER}
WORKDIR ${HOME}

# Install essentials
RUN apt-get update && \
    apt-get -y install clang python3-venv python3-dev && \
    apt-get purge && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Global site-wide config
RUN mkdir -p $HOME/.R/ \
    && echo "\nCXX=clang++ -ftemplate-depth-256\n" >> $HOME/.R/Makevars \
    && echo "CC=clang\n" >> $HOME/.R/Makevars

# Install rstan
RUN install2.r --error \
    inline \
    RcppEigen \
    StanHeaders \
    rstan \
    KernSmooth

# Config for rstudio user
RUN mkdir -p /home/rstudio/.R/ \
    && echo "\nCXX=clang++ -ftemplate-depth-256\n" >> /home/rstudio/.R/Makevars \
    && echo "CC=clang\n" >> /home/rstudio/.R/Makevars \
    && echo "CXXFLAGS=-O3\n" >> /home/rstudio/.R/Makevars \
    && echo "\nrstan::rstan_options(auto_write = TRUE)" >> /home/rstudio/.Rprofile \
    && echo "options(mc.cores = parallel::detectCores())" >> /home/rstudio/.Rprofile


# Create a venv dir owned by unprivileged user & set up notebook in it
# This allows non-root to install python libraries if required
RUN mkdir -p ${VENV_DIR} && chown -R ${NB_USER} ${VENV_DIR}

USER ${NB_USER}
RUN python3 -m venv ${VENV_DIR} && \
    pip3 install --no-cache-dir \
         notebook==5.2 \
         git+https://github.com/jupyterhub/nbrsessionproxy.git@6eefeac11cbe82432d026f41a3341525a22d6a0b \
         git+https://github.com/jupyterhub/nbserverproxy.git@5508a182b2144d29824652d8977b32302517c8bc && \
    jupyter serverextension enable --sys-prefix --py nbserverproxy && \
    jupyter serverextension enable --sys-prefix --py nbrsessionproxy && \
    jupyter nbextension install    --sys-prefix --py nbrsessionproxy && \
    jupyter nbextension enable     --sys-prefix --py nbrsessionproxy


RUN R --quiet -e "devtools::install_github('IRkernel/IRkernel')" && \
    R --quiet -e "IRkernel::installspec(prefix='${VENV_DIR}')"

RUN R -e "install.packages(c('kableExtra', 'ROCR', 'ISLR', 'ggridges', 'rstan', 'rstanarm', 'coda', 'mvtnorm', 'loo', 'MCMCpack', 'e1071', 'ggmap', 'Rtsne', 'NbClust', 'tree', 'maptree', 'glmnet', 'randomForest', 'ROCR', 'imager', 'plotmo'), repos = 'http://cran.us.r-project.org')" && \
    R -e "devtools::install_github("rmcelreath/rethinking")" && \
    R - e "devtools::install_github("gbm-developers/gbm3")"

RUN pip install jupyterhub==0.9.4

CMD jupyter notebook --ip 0.0.0.0
