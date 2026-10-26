import { S3Client, ListObjectsV2Command } from "@aws-sdk/client-s3";

const BUCKET = "archiver-demo-v1-public";

const client = new S3Client({ region: "us-east-1" });

export const handler = async (event) => {
  const request = event.Records[0].cf.request;
  console.log('got request', request.uri);
  const uri = request.uri.startsWith("/") ? request.uri.slice(1) : request.uri;
  const prefix = uri === "" ? "" : (uri.endsWith("/") ? uri : uri + "/");

  if (uri !== "" && !uri.endsWith("/")) return request;

  try {
    const list = await client.send(
      new ListObjectsV2Command({
        Bucket: BUCKET,
        Prefix: prefix === "/" ? "" : prefix,
        Delimiter: "/",
      })
    );

    const links = [];

    if (prefix !== "") {
      const parent =
        prefix.endsWith("/")
          ? prefix.slice(0, -1).split("/").slice(0, -1).join("/")
          : prefix.split("/").slice(0, -1).join("/");

      const parentHref = parent === "" ? "/" : `/${parent}/`;
      links.push(`<a href="${parentHref}">../</a>`);
    }

    if (list.CommonPrefixes)
      for (const d of list.CommonPrefixes)
        links.push(`<a href="/${d.Prefix}">${d.Prefix.substring(prefix.length)}</a>`);
    if (list.Contents)
      for (const f of list.Contents)
        if (f.Key !== prefix)
          links.push(`<a href="/${f.Key}">${f.Key}</a>`);

    const listHtml = links.map(l => `<li>${l}</li>`).join('\n    ');
    const body = `<html><head><title>Index of /${prefix}</title></head>
<body>
<h1>Index of /${prefix}</h1>
<hr><ul>
    ${listHtml}
</ul><hr>
</body></html>`;

    // origin-request Lambda@Edge body limit is 1 MB
    const MAX_BYTES = 900 * 1024;
    const safeBody = Buffer.byteLength(body, 'utf8') > MAX_BYTES
      ? body.slice(0, MAX_BYTES) + '\n<!-- listing truncated: too large -->'
      : body;

    return {
      status: "200",
      statusDescription: "OK",
      headers: {
        "content-type": [{ key: "Content-Type", value: "text/html; charset=utf-8" }],
      },
      body: safeBody,
    };
  } catch (err) {
    console.error('dirlist error:', err);
    return {
      status: "500",
      statusDescription: "Internal Server Error",
      headers: {
        "content-type": [{ key: "Content-Type", value: "text/html; charset=utf-8" }],
      },
      body: `<html><body><h1>Error listing /${prefix}</h1><p>${err.message}</p></body></html>`,
    };
  }
};
