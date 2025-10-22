# Grafana with Cloudflare Access Authentication

This guide explains how Grafana is configured to work with Cloudflare Access for single sign-on authentication.

## How It Works

1. **User accesses Grafana**: User navigates to `https://grafana.jeans-host.net`
2. **Cloudflare Access intercepts**: Cloudflare Access checks if the user is authenticated
3. **Authentication**: If not authenticated, redirects to your configured OAuth provider (Google, GitHub, etc.)
4. **Header injection**: Cloudflare adds authentication headers to the request:
   - `Cf-Access-Authenticated-User-Email`: User's email address
5. **Grafana trusts the header**: Grafana reads the email from the header and automatically logs in the user
6. **Auto-provisioning**: New users are automatically created with Viewer role

## Grafana Configuration

The following settings are configured in the HelmRelease:

```yaml
auth.proxy:
  enabled: true
  header_name: Cf-Access-Authenticated-User-Email
  header_property: email
  auto_sign_up: true
  whitelist: ""  # Allow all IPs since Cloudflare handles auth
  headers: "Name:Cf-Access-Authenticated-User-Email"

auth.anonymous:
  enabled: false

users:
  auto_assign_org: true
  auto_assign_org_role: Viewer  # Users start as Viewers
```

## Cloudflare Access Setup

### 1. Create a Cloudflare Access Application

In your Cloudflare dashboard:

1. Go to **Zero Trust** > **Access** > **Applications**
2. Click **Add an application** > **Self-hosted**
3. Configure:
   - **Application name**: Grafana
   - **Session duration**: Choose based on your security needs (e.g., 24 hours)
   - **Application domain**: `grafana.jeans-host.net`

### 2. Configure Access Policy

Create a policy to control who can access Grafana:

**Example Policy - Email domain based:**
```
Name: Allow company email
Action: Allow
Include:
  - Emails ending in: @yourdomain.com
```

**Example Policy - Specific users:**
```
Name: Allow specific users
Action: Allow
Include:
  - Email: user1@example.com
  - Email: user2@example.com
```

### 3. Identity Provider

Make sure you have an identity provider configured:
- Go to **Zero Trust** > **Settings** > **Authentication**
- Add providers like:
  - Google Workspace
  - GitHub
  - Microsoft Azure AD
  - Generic OIDC
  - One-time PIN (for email-based auth)

## User Roles

By default, users are created with the **Viewer** role. You can change this in the Grafana configuration:

- `Viewer`: Can view dashboards (default)
- `Editor`: Can create and edit dashboards
- `Admin`: Full Grafana administration

To change the default role, update this line in the HelmRelease:
```yaml
auto_assign_org_role: Editor  # or Admin
```

## Managing User Permissions

### Promoting Users to Admin/Editor

Once users are auto-created, you can promote them:

1. Log in to Grafana as admin (use the admin account with password `admin`)
2. Go to **Configuration** > **Users**
3. Find the user and change their role
4. Click **Update**

### Admin Emergency Access

The built-in admin account remains active for emergency access:
- **Username**: `admin`
- **Password**: `admin` (should be changed!)

This allows you to access Grafana even if Cloudflare Access is down.

## Security Considerations

### Important Notes

1. **Trust the proxy**: Grafana trusts the `Cf-Access-Authenticated-User-Email` header
2. **Cloudflare must be the only entry point**: Ensure Grafana is ONLY accessible through Cloudflare
3. **No direct cluster access**: The ingress should not be directly accessible from the internet
4. **Change admin password**: Update the default admin password for emergency access

### Recommended Security Settings

Since Cloudflare Access is handling authentication, ensure:

1. **Direct access blocked**: Configure your firewall/network policies to only allow traffic from Cloudflare IPs
2. **Service token validation**: Consider adding Cloudflare Access service token validation
3. **Audit logging**: Enable Cloudflare Access audit logs

## Testing

### Test the Integration

1. **Log out of Cloudflare**: Clear your browser cookies or use incognito mode
2. **Access Grafana**: Navigate to `https://grafana.jeans-host.net`
3. **Verify redirect**: You should be redirected to Cloudflare Access login
4. **Authenticate**: Log in with your configured identity provider
5. **Auto-login**: You should be automatically logged into Grafana

### Verify Auto-Provisioning

1. Access Grafana with a new user (who hasn't accessed before)
2. Log in to Grafana as admin
3. Go to **Configuration** > **Users**
4. Verify the new user was automatically created with Viewer role

## Troubleshooting

### User Not Auto-Created

Check the Grafana logs:
```bash
kubectl logs -n monitoring deployment/kube-prometheus-stack-grafana -c grafana | grep -i "auth\|proxy"
```

### Still Seeing Grafana Login Page

Possible causes:
1. Auth proxy not enabled properly - check ConfigMap:
   ```bash
   kubectl get configmap -n monitoring kube-prometheus-stack-grafana -o yaml | grep -A 10 "auth.proxy"
   ```
2. Cloudflare not sending headers - check request headers in browser DevTools
3. Grafana pod not restarted after config change - restart it:
   ```bash
   kubectl rollout restart deployment/kube-prometheus-stack-grafana -n monitoring
   ```

### Headers Not Being Passed

Verify Cloudflare is sending the authentication header:
1. Open browser DevTools (F12)
2. Go to Network tab
3. Access Grafana
4. Check request headers for `Cf-Access-Authenticated-User-Email`

If missing, verify your Cloudflare Access application configuration.

## Disabling Auth Proxy

If you need to disable Cloudflare Access integration and return to standard Grafana login:

1. Edit the HelmRelease:
   ```yaml
   auth.proxy:
     enabled: false
   ```
2. Commit and push the change
3. Let Flux reconcile, or manually trigger:
   ```bash
   flux reconcile helmrelease -n monitoring kube-prometheus-stack
   ```

## Additional Resources

- [Grafana Auth Proxy Documentation](https://grafana.com/docs/grafana/latest/setup-grafana/configure-security/configure-authentication/auth-proxy/)
- [Cloudflare Access Documentation](https://developers.cloudflare.com/cloudflare-one/applications/configure-apps/)
- [Cloudflare Access Headers](https://developers.cloudflare.com/cloudflare-one/identity/authorization-cookie/application-token/)
