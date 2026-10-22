# Front Door integration, deployed separately

Connects an **existing Function** and optionally an existing Web App. Creates a
Premium profile, endpoint and WAF by default, or adds routes to a supplied Premium
endpoint. It never creates or owns the origin apps, their plans or Storage.

Follow [component deployment](../../../docs/components.md#add-front-door-to-an-existing-function).
Use this directory's own state. Do not use this stack to take over routes owned by
another deployment. On a shared endpoint, review logo paths and (when adding the
website) `/*` conflicts before applying.
