#/bin/bash

# The following variable should be changed as needed
ADMIN_USER="admin"                   # user with enought privileges to run ipa commands.
PASSWORD="adminpassword"             # user password
GROUP="ipausers"                     # Group where to look for users with expired password.
SENDER="freeipa.noreply@example.com" # Sender used by sendmail
DISABLE_ACCOUNT_SUBJECT="Your FreeIPA account was disabled"
DISABLE_ACCOUNT_MAIL="Hello,\n\nYour password has expired.  Your FreeIPA account is disabled, to re-enable your account, please reach out to FreeIPA administrator.\n\nAs of now, you will no longer be able to access systems via SSH\n\nThank you,"

# Grace: how long password would be in expired state before disabling the user.
GRACE=1296000                        # 15 days

# kinit admin to be able to run the following commands
echo "$PASSWORD" | kinit "$ADMIN_USER"

#looping on all the users members of the GROUP (This to make sure we do not mistakinly reset password for other group/type of users)
for user in $(ipa user-find --in-groups="$GROUP" --raw | grep 'uid:' | awk '{ print $2; }' | sort | uniq) ; do
   #Making sure the user have a password to begin with
   if [[ $(ipa user-show $user | grep 'Password:' | awk '{ print $2; }') == "True" ]]; then
      # making sure not to loop over disabled account
      disabled=$(ipa user-show $user --all | grep 'Account disabled: ' | awk '{ print $3; }')
      if [[ $disabled == "False" ]]; then
         #Getting the expiration date of the password + some retarded hacks cause date on bash is not as powerfull as in zsh
         exprdate=$( ipa user-show $user --all | grep 'krbpasswordexpiration:' | awk '{ print $2; }' | sed 's/./&-/4' | sed 's/./&-/7' | sed 's/./& /10' | sed 's/./&:/13' | sed 's/./&:/16' | sed s'/.$//')
         let expr_period=`date +%s`-`date -d "$exprdate" +%s`
         # if password is expired
         if [[ $expr_period -gt 0 ]]; then
            RECEIVER=$(ipa user-show $user --all | grep 'Email address:'| awk '{ print $3; }')
            #If the password is past grace period we disable the user else send a reminder to the user
            if [[  $expr_period -gt $GRACE ]]; then
               echo "INFO: The user $user LDAP-EC2 account was disabled"
               ipa user-disable $user
               # working on sending the mail
               MAIL_TXT="Subject: $DISABLE_ACCOUNT_SUBJECT\nFrom: $SENDER\nTo: $RECEIVER\n\n$DISABLE_ACCOUNT_MAIL"
               echo -e $MAIL_TXT | sendmail -t
            else
               echo $user still have $(( ($GRACE-$expr_period) / 86400 )) days to reset his password
               #Sending the reminder mail
               # Kept those 2 here as we need the varibles $expr_period here. you can of course customize that.
               REMINDER_MAIL_SUBJECT="Your LDAP-EC2 password will expire in $(( ($GRACE-$expr_period) / 86400 )) days"
               REMINDER_MAIL_BODY="Hello,\n\nYour LDAP-EC2 password will expire in $(( ($GRACE-$expr_period) / 86400 )) days. This password is used for SSH access to systems, ...\n\nPlease visit freeipa.example.com to change your password before it expires to prevent access loss to freeipa managed services listed above.\n\nThank you."
               MAIL_TXT="Subject: $REMINDER_MAIL_SUBJECT\nFrom: $SENDER\nTo: $RECEIVER\n\n$REMINDER_MAIL_BODY"
               echo -e $MAIL_TXT | sendmail -t
             fi
         fi
      fi
   fi
done
