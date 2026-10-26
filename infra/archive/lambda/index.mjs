import { S3Client, ListObjectsV2Command } from "@aws-sdk/client-s3";

const BUCKET = "archiver-demo-v1-public";

const client = new S3Client({ region: "us-east-1" });

export const handler = async (event) => {
  const request = event.Records[0].cf.request;
  console.log('got request', request.uri)
  const uri = request.uri.startsWith("/") ? request.uri.slice(1) : request.uri;
  const prefix = uri === "" ? "" : (uri.endsWith("/") ? uri : uri + "/");

  if (uri !== "" && !uri.endsWith("/")) return request;


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

  const body = `
    <html><head><title>Index of /${prefix}</title></head>
    <body>
    <h1>Index of /${prefix}</h1>
    <hr>
    <ul>
        ${links.map(l => `<li>${l}</li>`).join('\n\t')}
    </ul>
    <hr>
    </body></html>
  `;

  return {
    status: "200",
    statusDescription: "OK",
    headers: {
      "content-type": [{ key: "Content-Type", value: "text/html; charset=utf-8" }],
    },
    body,
  };
};
