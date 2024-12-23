ARG NODE_VERSION=18
FROM n8nio/base:${NODE_VERSION}

ARG N8N_VERSION=1.27.1
RUN if [ -z "$N8N_VERSION" ] ; then echo "The N8N_VERSION argument is missing!" ; exit 1; fi

ENV N8N_VERSION=${N8N_VERSION}
ENV NODE_ENV=production
ENV N8N_RELEASE_TYPE=stable
RUN set -eux; \
	npm install -g --omit=dev n8n@${N8N_VERSION} --ignore-scripts && \
	npm rebuild --prefix=/usr/local/lib/node_modules/n8n sqlite3 && \
	rm -rf /usr/local/lib/node_modules/n8n/node_modules/@n8n/chat && \
	rm -rf /usr/local/lib/node_modules/n8n/node_modules/n8n-design-system && \
	rm -rf /usr/local/lib/node_modules/n8n/node_modules/n8n-editor-ui/node_modules && \
	find /usr/local/lib/node_modules/n8n -type f -name "*.ts" -o -name "*.js.map" -o -name "*.vue" | xargs rm -f && \
	rm -rf /root/.npm

COPY docker-entrypoint.sh /
RUN chmod 777 /docker-entrypoint.sh

RUN apk update && apk add curl python3 bash su-exec

RUN curl https://dl.google.com/dl/cloudsdk/release/google-cloud-sdk.tar.gz > /tmp/google-cloud-sdk.tar.gz

RUN mkdir -p /usr/local/gcloud \
  && tar -C /usr/local/gcloud -xvf /tmp/google-cloud-sdk.tar.gz \
  && /usr/local/gcloud/google-cloud-sdk/install.sh \
  && rm -rf /tmp/google-cloud-sdk.tar.gz

ENV PATH=$PATH:/usr/local/gcloud/google-cloud-sdk/bin

RUN mkdir .n8n && \
    chown node:node .n8n && \
    chmod 700 .n8n
USER root

ENV N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true
ENV N8N_SECURE_COOKIE=false

ENTRYPOINT ["tini", "--", "/docker-entrypoint.sh"]