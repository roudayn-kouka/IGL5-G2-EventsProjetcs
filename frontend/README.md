# Events Management frontend

Angular standalone frontend for the existing Spring Boot API. It uses `/events` as its default API base, so a production ingress can route both the SPA and the API without embedding an ELB hostname in the bundle.

## Local development

Start the backend on port `8089`, then:

```powershell
cd frontend
npm.cmd install
npm.cmd start
```

Open `http://localhost:4200`. The Angular proxy forwards `/events/*` to `http://localhost:8089/events/*`.

## Checks and image

```powershell
npm.cmd run build
npm.cmd test
docker build -t events-frontend:local .
docker run --rm -p 8080:8080 events-frontend:local
```

The image serves SPA routes with NGINX. In production it expects the reverse proxy/ingress to expose the Spring API at the same-origin path `/events`; no cloud hostname or credentials are bundled.
