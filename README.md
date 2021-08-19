# AWS Notion (reverse) Proxy

This piece of code runs in AWS Lambda, forwards requests to [Notion][1]'s server. If you have a public accessible
Notion page, you can host it in your own domain, to make it feel like a standalone website.

We host our company handbook (still working in progress) with it: https://vibe.pub

## Why
There are many SaaS for this purpose.  [Super][2], [Hostnotion][3] just to name a few. While they're easy to use, and
work perfectly most of the time, we have some special requirements that are not well supported by these services.

Our public company handbook contains private links which should only be accessed by employees. We would like to have
seamless experience for employees who click these private links, to be redirected to notion for authentication, and
in most case, automatically logged in and taken to the pages.  None of the SaaS service providers does this in the
right way.  So we decided to build our own.

## How
We use AWS API Gateway to forward requests to Notion's server, and inject some JS code to redirect once a Login modal
is detected.  We didn't choose Lambda@Edge because it has 1MB payload limit, and Notion's app.js is almost 1MB after
compression.

## Deploy
We use [Chalice][4] to manage AWS infrasuture for this tiny project.

```shell
virtualenv .venv
source .venv/bin/activate
pip install -r requirements.txt

chalice deploy
```

---

Kudos to https://github.com/xanthous-tech/aws-notion-site.  We borrowed some ideas there, fixed several issues,
and added our own requirements on top of it.

[1]: https://notion.so
[2]: https://super.so
[3]: https://hostnotion.co
[4]: https://github.com/aws/chalice
