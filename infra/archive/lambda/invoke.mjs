import { handler } from './index.mjs'
const payload = {
  "Records": [
    {
      "cf": {
        "config": {
          "distributionId": "EXAMPLE"
        },
        "request": {
          "headers": {
            "host": [
              {
                "key": "Host",
                "value": "d123.cf.net"
              }
            ],
            "user-name": [
              {
                "key": "User-Name",
                "value": "CloudFront"
              }
            ]
          },
          "clientIp": "2001:cdba::3257:9652",
          "uri": "/archive/urls/",
          "method": "GET"
        },
        "response": {
          "status": "200",
          "statusDescription": "OK",
          "headers": {
            "x-cache": [
              {
                "key": "X-Cache",
                "value": "Hello from Cloudfront"
              }
            ]
          }
        }
      }
    }
  ]
}

const res = (await handler(payload))

console.log('='.repeat(10))
console.log('Status:', res.status)
console.log('='.repeat(10))
console.log(res.body)

