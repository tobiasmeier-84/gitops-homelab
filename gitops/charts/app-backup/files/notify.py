import os
import smtplib
from email.mime.application import MIMEApplication
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText

status = os.environ["STATUS"]
result = os.environ.get("RESULT", "")
run_id = os.environ["RUN_ID"]
app_name = os.environ["APP_NAME"]

msg = MIMEMultipart()
msg["From"] = "backup@solsys.dev"
msg["To"] = os.environ["NOTIFY_EMAIL"]
msg["Subject"] = f"{app_name} backup {status}: {run_id}"
msg.attach(MIMEText(f"Backup run {run_id} for {app_name}: {status}.\n\n{result}\n\nFull log attached.", "plain"))

try:
    with open("/tmp/worker-output.log", "rb") as f:
        part = MIMEApplication(f.read(), Name=f"backup-{run_id}.log")
    part["Content-Disposition"] = f'attachment; filename="backup-{run_id}.log"'
    msg.attach(part)
except FileNotFoundError:
    pass

s = smtplib.SMTP_SSL("mail.cyon.ch", 465)
s.login(os.environ["smtp_username"], os.environ["smtp_password"])
s.sendmail("backup@solsys.dev", os.environ["NOTIFY_EMAIL"], msg.as_string())
s.quit()
print("Notification sent.")
