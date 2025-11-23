def lambda_handler(event, context):
    """
    Cognito Pre Sign-up trigger: allow only @sjsu.edu emails.
    Attach this to the user pool Pre sign-up trigger.
    """
    email = event.get("request", {}).get("userAttributes", {}).get("email", "")
    if not email:
        # No email provided — reject
        raise Exception("Email required")

    email = email.lower()
    if not email.endswith("@sjsu.edu"):
        # Reject sign-up for other domains
        raise Exception("Only @sjsu.edu email addresses are allowed to register.")

    # Optionally auto-confirm and auto-verify the email to skip verification step:
    event.setdefault("response", {})["autoConfirmUser"] = True
    event["response"]["autoVerifyEmail"] = True

    return event