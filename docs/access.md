# Access control - SSH

Access to the machines should be RBAC-ed, short lived and  easy to revoke

## Current Implementation

- Terraform generates keys to ssh into the machines
- Initially stored locally, but transferred via SSH to bastion server

> It doesn't satisfy above conditions


## Possible solutions:

- Vault
   - Signed SSH Certificates
   - One-time SSH Passwords
   
- SSH Cashier https://github.com/nsheridan/cashier

- https://smallstep.com/blog/use-ssh-certificates/ Simliar to above, where they use a trusted entity to hand out keys(short lived) to authenticated users