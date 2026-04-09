# Pending Approval

How to handle transactions that return `status=pending_approval` — the required approval flow depends on whether the wallet has an owner linked.

## Check owner_linked

Always check `owner_linked` before telling the user how to approve:

```bash
caw status | jq .owner_linked
```

Or read it from the response of any `caw status` call earlier in the conversation.

## owner_linked = false — approve in this conversation

The wallet has no linked owner yet. Approval happens directly in this conversation — the user decides, and the agent executes their decision. Ask the user to reply with their decision directly in the chat:

> "This transaction requires your approval before it can proceed.
> Transaction ID: `<request_id>`
> Amount: `<amount>` `<token>` → `<recipient>`
>
> Please reply **approve** or **reject**."

Once the user replies:
- **approve** → call `caw pending approve <pending_operation_id>`
- **reject** → call `caw pending reject <pending_operation_id>`

The `pending_operation_id` is returned in the original `caw tx transfer` / `caw tx call` response as `result.pending_operation_id`.

## owner_linked = true — approve in Human App

The wallet owner must approve via the Cobo Human App (mobile). Inform the user:

> "This transaction requires approval from the wallet owner in the Cobo Human App.
> Transaction ID: `<request_id>`
> Amount: `<amount>` `<token>` → `<recipient>`
>
> Please open the Human App and approve the pending operation. I'll continue once it's approved."

Do NOT call `caw pending approve` — that requires the owner's credentials. Poll for completion instead:

```bash
caw pending get <pending_operation_id>
# Check .status: pending → approved → (transaction executes) / rejected
```

## Getting pending_operation_id

The `pending_operation_id` is in the submit response:

```bash
caw tx transfer ... | jq .result.pending_operation_id
```

If the transfer was submitted earlier and you no longer have the response, list pending operations:

```bash
caw pending list | jq '.result.items[] | select(.request_id == "<request_id>")'
```