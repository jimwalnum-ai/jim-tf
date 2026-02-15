# add record in bassa.ldif via ldapadd
ldapadd -x -H ldap://localhost -D "cn=admin,dc=crimosonscallion,dc=com" -f cs.ldif -w alliumavenger

