import imaplib
import os
import smtplib
import ssl
import time
import uuid
from email.message import EmailMessage
from pathlib import Path

HOST = os.environ.get("MAIL_HOST", "127.0.0.1")
DOMAIN = os.environ.get("MAIL_DOMAIN", "corp.local")
SMTP_PORT = int(os.environ.get("SMTP_PORT", "25"))
SUBMISSION_PORT = int(os.environ.get("SUBMISSION_PORT", "587"))
IMAP_PORT = int(os.environ.get("IMAP_PORT", "143"))
GREYLIST_WAIT = int(os.environ.get("GREYLIST_WAIT", "420"))
ANTIVIRUS_WAIT = int(os.environ.get("ANTIVIRUS_WAIT", "90"))
CHECK_ANTIVIRUS = os.environ.get("CHECK_ANTIVIRUS", "1") == "1"
GTUBE = "XJS*C4JDBQADN1.NSBN3*2IDNEN*GTUBE-STANDARD-ANTI-UBE-TEST-EMAIL*C.34X"
EICAR = r"X5O!P%@AP[4\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*"
TLS = ssl.create_default_context()
TLS.check_hostname = False
TLS.verify_mode = ssl.CERT_NONE


def load_credentials() -> dict[str, str]:
    path = Path(__file__).resolve().parents[1] / "secrets" / "credentials.env"
    return dict(line.split("=", 1) for line in path.read_text().splitlines() if "=" in line)


def message(sender: str, recipient: str, subject: str, body: str) -> EmailMessage:
    mail = EmailMessage()
    mail["From"] = sender
    mail["To"] = recipient
    mail["Subject"] = subject
    mail.set_content(body)
    return mail


def submit(user: str, password: str, mail: EmailMessage) -> None:
    with smtplib.SMTP(HOST, SUBMISSION_PORT, timeout=30) as smtp:
        smtp.starttls(context=TLS)
        smtp.login(user, password)
        smtp.send_message(mail)


def deliver_from_outside(mail: EmailMessage) -> tuple[int, str]:
    with smtplib.SMTP(HOST, SMTP_PORT, timeout=60) as smtp:
        smtp.ehlo("mx.external.test")
        try:
            smtp.send_message(mail)
        except smtplib.SMTPDataError as error:
            return error.smtp_code, error.smtp_error.decode(errors="replace")
        except smtplib.SMTPRecipientsRefused as error:
            code, text = next(iter(error.recipients.values()))
            return code, text.decode(errors="replace")
    return 250, "accepted"


def fetch_headers(user: str, password: str, subject: str) -> str:
    for _ in range(20):
        with imaplib.IMAP4(HOST, IMAP_PORT, timeout=30) as imap:
            imap.starttls(ssl_context=TLS)
            imap.login(user, password)
            imap.select("INBOX", readonly=True)
            _, found = imap.search(None, "SUBJECT", f'"{subject}"')
            if ids := found[0].split():
                _, data = imap.fetch(ids[-1], "(BODY.PEEK[HEADER])")
                return data[0][1].decode(errors="replace")
        time.sleep(3)
    raise AssertionError(f"message '{subject}' did not reach {user}")


def check(title: str, condition: bool, detail: str) -> bool:
    print(f"[{'OK' if condition else 'FAIL'}] {title}: {detail}")
    return condition


def main() -> int:
    creds = load_credentials()
    alice, bob = f"alice@{DOMAIN}", f"bob@{DOMAIN}"
    token = uuid.uuid4().hex[:8]
    results = []

    subject = f"smoke internal {token}"
    submit(alice, creds["ALICE_PASSWORD"], message(alice, bob, subject, "Проверка доставки внутри домена."))
    fetch_headers(bob, creds["BOB_PASSWORD"], subject)
    results.append(check("submission 587 + SASL -> LMTP -> IMAP", True, f"письмо '{subject}' в INBOX {bob}"))

    subject = f"smoke external {token}"
    incoming = message(f"partner-{token}@external.test", bob, subject, "Входящее письмо извне.")
    code, text = deliver_from_outside(incoming)
    print(f"[INFO] first delivery attempt from unknown sender: {code} {text}")
    deadline = time.monotonic() + GREYLIST_WAIT
    while code == 451 and time.monotonic() < deadline:
        time.sleep(30)
        code, text = deliver_from_outside(incoming)
    results.append(check("SMTP 25 from external after retry", code == 250, f"{code} {text}"))
    headers = fetch_headers(bob, creds["BOB_PASSWORD"], subject)
    scanned = "X-Spamd-Result" in headers and "X-Spam-Status" in headers
    results.append(check("rspamd milter headers", scanned, "X-Spamd-Result и X-Spam-Status во входящем письме"))

    try:
        submit(alice, "wrong-password", message(alice, bob, "bad auth", "x"))
        results.append(check("SASL rejects wrong password", False, "письмо принято"))
    except smtplib.SMTPAuthenticationError as error:
        results.append(check("SASL rejects wrong password", True, f"{error.smtp_code}"))

    code, text = deliver_from_outside(message("spammer@external.test", "nobody@example.org", "relay", "x"))
    results.append(check("no open relay", code >= 500, f"{code} {text}"))

    code, text = deliver_from_outside(message("spammer@external.test", bob, f"gtube {token}", GTUBE))
    results.append(check("rspamd rejects GTUBE spam", code >= 500, f"{code} {text}"))

    if CHECK_ANTIVIRUS:
        virus = message("attacker@external.test", bob, f"eicar {token}", "Вложение во вложении.")
        virus.add_attachment(EICAR.encode(), maintype="text", subtype="plain", filename="readme.txt")
        deadline = time.monotonic() + ANTIVIRUS_WAIT
        code, text = deliver_from_outside(virus)
        while "virus" not in text and time.monotonic() < deadline:
            print(f"[INFO] antivirus not ready yet: {code} {text}")
            time.sleep(10)
            code, text = deliver_from_outside(virus)
        results.append(check("clamav rejects EICAR", code >= 500 and "virus" in text, f"{code} {text}"))

    print(f"{sum(results)}/{len(results)} checks passed")
    return 0 if all(results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
