# Interview Prep — Image Processing AWS Platform (Q&A)

Simple, plain-language answers to go with the question list. Use these as a base and add your own personal touches (what you struggled with, what you'd do differently) — interviewers like hearing that more than a textbook answer.

---

## 1. Architecture & System Design

**Q: Walk through the full lifecycle of an image, AWS path.**
A: User picks an image and a mode (resize/compress/convert/thumbnail) in the browser. The frontend asks the upload Lambda (via API Gateway) for a pre-signed S3 upload URL. The browser then uploads the file straight to the private "uploads" bucket using that URL. S3 sees the new file and automatically triggers the process Lambda, which downloads the file, runs Pillow on it, and saves the result to the "processed" bucket. The frontend keeps checking (polling) `/gallery`, which asks the gallery Lambda to list processed files and hand back short-lived download links.

**Q: Why pre-signed URL upload instead of sending the file through Lambda/API Gateway?**
A: API Gateway and Lambda have payload size limits and cost money per request based on time/data. If the file goes straight from browser to S3, Lambda only has to do a tiny bit of work (just generate a signed link), and S3 handles the actual heavy lifting of receiving the file. It's cheaper, faster, and avoids size limits.

**Q: Why process asynchronously with an S3 trigger instead of doing it in the same Lambda as the upload?**
A: The upload Lambda's only job is to hand out a signed URL — it never even sees the actual image bytes, so it *can't* process the image at that point. Also, keeping upload and processing separate means a slow or failing image-processing step doesn't block or slow down the upload response the user is waiting on.

**Q: What's wrong with polling every 3 seconds for 30 seconds, and what's better?**
A: Polling wastes requests when nothing has changed yet, adds delay (up to 3 seconds late), and gives up after 30 seconds even if processing is still going. Better options: WebSockets (server pushes a message the moment processing finishes) or having S3 send an event to something like SNS/SQS that notifies the frontend, so the client finds out immediately instead of guessing.

**Q: Why two separate buckets (uploads vs processed) instead of one bucket with folders?**
A: Separate buckets make permissions simpler and safer — the upload Lambda only needs "write" access to one bucket, the gallery Lambda only needs "read" access to the other. It also makes lifecycle rules easier (e.g., auto-delete raw uploads after a few days) and avoids accidentally triggering the process Lambda again on processed files landing in the same bucket.

**Q: How would you avoid duplicating the image-processing logic between Flask and Lambda?**
A: Pull the actual Pillow logic (resize/compress/convert/thumbnail) into one small shared Python module/package. Both `backend/services/image_services.py` and `terraform/lambda/process/handler.py` would import from that shared module instead of each having their own copy. This way a bug fix or new mode only needs to be written once.

**Q: What breaks first at 10,000 concurrent uploads, and how do you fix it?**
A: A few likely pain points: Lambda concurrency limits (too many process Lambdas trying to run at once), the gallery Lambda listing *all* objects with no pagination (gets slower and slower as the bucket grows), and API Gateway/Lambda cold starts under sudden load. Fixes: add reserved/provisioned concurrency, add pagination + maybe a DynamoDB table to track processed files instead of listing S3 directly, and consider a queue (SQS) in front of processing to smooth out spikes.

---

## 2. AWS-Specific

**Q: Explain how a pre-signed URL works.**
A: AWS lets you generate a normal S3 URL but with extra signed information attached (expiry time, allowed action, and a cryptographic signature made with the server's AWS credentials). Anyone holding that URL can do the one allowed action (e.g., PUT a file) without having any AWS credentials themselves, because S3 checks the signature and expiry instead of checking who's asking.

**Q: What IAM permissions does the Lambda need, and how do you scope them tightly?**
A: The upload Lambda only needs `s3:PutObject` on the uploads bucket. The process Lambda needs `s3:GetObject` on uploads and `s3:PutObject` on processed. The gallery Lambda only needs `s3:GetObject`/`s3:ListBucket` on processed. Least privilege means giving each Lambda only the exact actions and exact bucket it needs — never `s3:*` on `*`.

**Q: How does S3 trigger the process Lambda?**
A: In Terraform, you configure an S3 "event notification" on the uploads bucket for the `ObjectCreated` event, pointing it at the process Lambda's ARN, plus a Lambda permission that allows S3 to invoke it. So the moment a new object appears, S3 calls the Lambda automatically — no polling needed on that side.

**Q: What if the process Lambda fails (bad image, Pillow error)?**
A: Right now there's no visible retry/dead-letter setup described. If it just fails, the file silently never gets processed. A better setup: wrap the Pillow call in try/except, log the error, and configure a Dead Letter Queue (SQS) or Lambda "on-failure destination" so failed events aren't lost and can be inspected or retried later.

**Q: Why is hardcoding the region to `eu-north-1` a problem?**
A: It means the code only works in one AWS region — if you ever deploy to another region (e.g., for latency or disaster recovery), the Lambda would still try to talk to `eu-north-1` and break. Fix: read the region from an environment variable (Terraform already knows `aws_region`) and pass it into the Lambda's config, so the code adapts automatically.

**Q: What about Lambda's `/tmp` size limit with large images?**
A: Lambda gives you about 512 MB of `/tmp` space by default (configurable up to 10 GB). If someone uploads a huge image, the download-to-`/tmp` step could run out of space and the Lambda would crash. Fixes: increase the `/tmp` size in Lambda config, or stream/process the image in chunks instead of loading the whole thing at once, or reject oversized uploads earlier.

**Q: What about cold starts with a heavy dependency like Pillow?**
A: Because Pillow (a native C library) is vendored into the Lambda package, the deployment package is bigger, which can make "cold starts" (the first request after idle time) slower, since AWS has to load more code into memory. Fixes: use Lambda's provisioned concurrency to keep instances warm, or use Lambda layers to separate the big dependency from your handler code so it loads more efficiently.

**Q: Why is "no pagination" in the gallery Lambda a problem?**
A: S3's `ListObjectsV2` only returns up to 1,000 objects per call. If the processed bucket ever has more files than that, the gallery would silently miss files. It also gets slower over time as more images pile up, since it always has to list everything. Fix: use pagination tokens to page through results, or better, keep a lightweight index (like a DynamoDB table) that's updated whenever a file is processed, and query that instead of listing S3 directly.

**Q: REST API vs HTTP API in API Gateway — why HTTP API here?**
A: HTTP APIs are simpler, cheaper, and have lower latency than the older REST APIs, but with fewer advanced features (like request validation or usage plans). For a project like this — simple routes, no need for API keys or complex request transformation — HTTP API is a good, cost-effective fit.

**Q: Why is bucket versioning enabled, and what's the downside?**
A: Versioning keeps old copies of a file whenever it's overwritten, which protects against accidental deletes/overwrites and helps with auditing. The downside is storage cost — every version of every file sticks around forever unless you set up a lifecycle rule to expire old versions, so costs can quietly grow over time.

---

## 3. Security

**Q: Private buckets + pre-signed URLs — what's the real attack surface? What if a URL leaks?**
A: The main risk is if a pre-signed URL gets shared or leaked (e.g., copy-pasted somewhere public) — anyone with that link can use it until it expires (the gallery links expire after 1 hour). Since it's time-limited and scoped to one object/action, the damage is contained compared to a fully public bucket, but you should still keep expiry times short and never log full URLs somewhere insecure.

**Q: CORS is wide open for dev — what's the risk, and the fix?**
A: Allowing "any origin" means any website on the internet could make requests to your API from a user's browser, which could be abused for things like scraping your data or, combined with other bugs, cross-site request issues. Fix: restrict `Access-Control-Allow-Origin` to just your actual frontend domain (e.g., the S3 website URL) once you move to production.

**Q: The upload Lambda trusts the client's `contentType` — what could go wrong?**
A: A malicious user could send a fake content type (e.g., claim a script file is `image/jpeg`) to get a signed URL and then upload something that isn't really an image. Since the process Lambda just tries to run Pillow on whatever's uploaded, it should be validating the actual file (checking real image "magic bytes," not just trusting the label) before processing, and ideally scanning/validating in the process Lambda too.

**Q: SSE-S3 vs SSE-KMS — what's the difference?**
A: SSE-S3 (used here, AES256) means AWS manages the encryption keys for you automatically — simple, free, less control. SSE-KMS uses AWS Key Management Service, giving you your own key you control, key rotation policies, and detailed audit logs of who used the key — useful when you need stricter compliance or want to control/revoke access to the key itself.

**Q: No deep file validation — what's the risk, and the fix?**
A: Just checking the extension or content-type is easy to fake — someone could rename any file to `.jpg` and it would pass the current check. Fixes: check the actual file bytes/"magic numbers" to confirm it's really an image, set a max file size limit, and consider scanning uploads for malware before/after processing.

---

## 4. Backend / Python

**Q: Why sanitize the filename AND add a UUID prefix?**
A: `secure_filename` strips out dangerous characters (like `../` or special symbols) so a filename can't be used to break out of the intended folder or overwrite system files. The UUID prefix on top of that guarantees two different users uploading a file with the exact same name won't overwrite each other's files.

**Q: `thumbnail()` vs `resize()` in Pillow — why thumbnail?**
A: `resize()` forces the image into the exact width/height you give it, which can stretch or squish the picture. `thumbnail()` shrinks the image to *fit inside* a box (like 800×800) while keeping the original aspect ratio, so the image doesn't look distorted.

**Q: The `convert` mode writes JPEG but keeps the original extension — what's the bug, and the fix?**
A: If someone uploads a `.png` and picks "convert," the actual file saved is JPEG bytes, but the object key still ends in `.png`. A browser or app opening that file might get confused about its real format. Fix: when the mode is `convert`, force the output key/extension to `.jpg` regardless of what was originally uploaded.

**Q: How would you make the Flask route handle a bad `processType` gracefully?**
A: Right now an invalid mode probably just causes an unhandled error. A better version would validate `processType` against the allowed list first and return a clean `400 Bad Request` with a helpful JSON error message if it's not valid, instead of letting Pillow or the code crash with a raw exception.

**Q: Flask-CORS vs manual CORS handling — what's happening with preflight OPTIONS requests?**
A: When a browser makes certain cross-origin requests (like a `PUT` with custom headers), it first sends an automatic `OPTIONS` "preflight" request asking "are you okay with this?" before sending the real request. Flask-CORS handles answering that preflight automatically with the right headers; doing it manually means writing that OPTIONS-handling logic yourself for every route.

---

## 5. Frontend / JavaScript

**Q: Why use `URL.createObjectURL` for the preview instead of waiting for the server?**
A: `createObjectURL` lets the browser show the picked image *immediately*, using only the file already sitting in the browser's memory — no network request needed at all. This makes the app feel instant and doesn't waste time/bandwidth uploading just to show a preview.

**Q: Why build gallery cards with DOM APIs instead of `innerHTML`?**
A: Pre-signed URLs contain special characters in their query string (like `&`, `=`, `%`). If you build HTML by directly inserting that URL into a string and setting `innerHTML`, those characters can get accidentally escaped or misinterpreted, breaking the link/signature. Using DOM APIs (like `setAttribute('src', url)`) inserts the raw string safely without any HTML-escaping side effects.

**Q: Why fetch-as-blob for downloads instead of `<a href={url} download>`?**
A: Since the S3 URL is on a different origin (cross-origin) than the app, a plain `download` attribute link often gets blocked or just opens the file in a new tab instead of downloading it, because of browser cross-origin download rules. Fetching the file as a blob first and creating a local object URL from that blob avoids those cross-origin quirks entirely, since the download link is now local to the page.

**Q: How would you replace the 3-second poll with something better?**
A: Instead of the frontend repeatedly asking "is it ready yet?", have the backend push the update once it's actually ready — either through a WebSocket connection, or through a simpler approach like Server-Sent Events, or by having S3's event trigger also notify a small notification service that tells the browser directly. This removes wasted requests and removes the "up to 30 seconds and then give up" limitation.

---

## 6. Infrastructure as Code (Terraform)

**Q: Walk through what `terraform plan` shows for this stack.**
A: It would show it's about to create: three S3 buckets (uploads, processed, frontend) with their policies/CORS settings, IAM roles and policies for each Lambda, three Lambda functions (upload, process, gallery), the API Gateway HTTP API with its routes (`POST /upload`, `GET /gallery`), and the S3 event notification connecting the uploads bucket to the process Lambda.

**Q: Why use Terraform's `archive` provider instead of committing pre-built zip files?**
A: If you commit the zip files directly, they can go stale (you forget to rebuild them after changing the handler code) and they bloat the git repo with binary files. The `archive` provider automatically zips up your current source code every time you run Terraform, so the deployed code always matches what's actually in your source files.

**Q: `.terraform`, state files, and build zips are in the working tree — why risky, and how to fix?**
A: Terraform state files can contain sensitive info (like resource IDs, sometimes secrets) and if multiple people are working on it, committing state to git causes conflicts and can corrupt your infrastructure's "source of truth." Fix: add these to `.gitignore`, and store state remotely instead (e.g., an S3 bucket + DynamoDB table for locking), so it's shared safely and never touched directly by hand.

**Q: How would you support multiple environments (dev/staging/prod)?**
A: Two common approaches: (1) Terraform "workspaces," which let you reuse the same `.tf` files but keep separate state per environment, or (2) fully separate folders/state files per environment with their own `terraform.tfvars` (different `project_name`/`environment` values). Separate state per environment is usually safer for production, since a mistake in dev can't accidentally affect prod's state.

---

## 7. Trade-offs & "Why Not X"

**Q: Why serverless (Lambda) instead of a container (ECS/Fargate)?**
A: For a task that runs only occasionally (whenever someone uploads an image), Lambda means you pay only for the actual seconds it runs, and you don't have to manage or pay for a server sitting idle. A container makes more sense if processing is constant/high-volume, needs a very long runtime, or needs specific system dependencies that don't fit Lambda's constraints.

**Q: Cost implications of Lambda-per-image vs a persistent server?**
A: At low volume, Lambda is far cheaper since a persistent server (EC2/Fargate) costs money 24/7 even when nobody's uploading anything. At very high, constant volume, a persistent server can become cheaper per-request than Lambda, since Lambda's per-invocation pricing adds up at scale.

**Q: Why not just do everything in Flask on EC2 and skip serverless entirely?**
A: The serverless approach avoids managing/patching a server, scales automatically (no capacity planning needed), and only costs money when actually used. The trade-off is more moving parts (three separate Lambdas, event wiring, IAM roles) and vendor lock-in to AWS's way of doing things — Flask on EC2 is simpler to reason about but you're responsible for uptime, scaling, and patching yourself.

**Q: How would you fix the hardcoded API URL in the frontend?**
A: Put the API URL in one single config file/constant (or generate it automatically from a Terraform output during deployment) instead of it appearing in multiple places in `script.js`. That way, changing environments or redeploying only requires updating one value instead of hunting through the code.

---

## 8. Testing, Reliability, Observability

**Q: No test suite exists — what would you add first?**
A: Priority order: unit tests for the Pillow processing logic (resize/compress/convert/thumbnail, since that's the core business logic and easy to test with sample images), then tests for the Lambda handlers using mocked `boto3` calls (so you don't need real AWS to test the logic), then basic Flask route tests (valid/invalid uploads, missing fields).

**Q: How would you add monitoring here?**
A: Turn on CloudWatch Logs for all three Lambdas (already automatic, but make sure error logging is meaningful), set up CloudWatch Alarms on Lambda error rates and API Gateway 5xx responses, and consider tracing (AWS X-Ray) to see where time is spent across the upload → process → gallery flow.

**Q: How would you test the S3-triggered Lambda without deploying to AWS?**
A: Tools like `moto` (mocks AWS services in Python tests) let you simulate S3 put events and check your Lambda code responds correctly, without ever touching real AWS. For a more full environment simulation, LocalStack can spin up fake S3/Lambda locally, or AWS SAM CLI can invoke a Lambda locally with a sample event payload.

---

## 9. Deep-Dive / Curveball

**Q: Why can the browser PUT directly to a private S3 bucket without its own AWS credentials?**
A: Because the *signature* on the pre-signed URL was already generated server-side (by the Lambda, using its own credentials) ahead of time. S3 checks that signature, not who's making the request — so the browser doesn't need any credentials of its own; it's just using a URL that was pre-authorized by someone who does have credentials.

**Q: Two users upload files with the identical original filename at the same time — how are collisions avoided?**
A: Every uploaded file gets a new key shaped like `{processType}_{uuid}.{ext}` — the UUID is randomly generated per upload, so even if both users upload "photo.jpg," they get two completely different, unique object keys and never overwrite each other.

**Q: What breaks if the `Content-Type` used in the actual PUT doesn't match what was signed?**
A: Pre-signed URLs can be tied to a specific `Content-Type` as part of what was signed. If the browser sends a different content type than what was originally requested/signed, S3 will reject the upload with a signature mismatch error, since the request no longer matches what was authorized.

**Q: How would you guarantee exactly-once processing (never double-process the same upload)?**
A: A couple of options: make the process Lambda idempotent (check if the processed file already exists before doing the work again, so even if it runs twice, the outcome is the same), or use S3 event de-duplication with a tracking table (like DynamoDB) that records which keys have already been processed, and skip any key that's already marked done.

---

*Tip: When you actually get asked these in an interview, don't just recite the answer — mention the specific line from your own project (e.g., "in my `terraform/lambda/process/handler.py`...") so it's clear you built and understand it, not memorized it.*
