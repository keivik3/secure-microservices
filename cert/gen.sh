#!/bin/sh
# Генерация своего CA и сертификатов для mTLS между сервисами.
# Порт cert/gen.sh из Go-версии. Перед запуском положите рядом
# opensslCA.cnf, opensslServer.cnf, server-ext.cnf, client-ext.cnf.

rm -f *.pem

# 1. Свой удостоверяющий центр (CA)
openssl req -x509 -newkey rsa:4096 -days 365 -nodes \
  -keyout ca-key.pem -out ca-cert.pem -config opensslCA.cnf

echo "CA's self-signed certificate"
openssl x509 -in ca-cert.pem -noout -text

# 2. Серверный сертификат, подписанный нашим CA
openssl req -newkey rsa:4096 -nodes \
  -keyout server-key.pem -out server-req.pem -config opensslServer.cnf

openssl x509 -req -in server-req.pem -days 60 \
  -CA ca-cert.pem -CAkey ca-key.pem -CAcreateserial \
  -out server-cert.pem -extfile server-ext.cnf

echo "Server's signed certificate"
openssl x509 -in server-cert.pem -noout -text

# 3. Клиентский сертификат (для сервисов-клиентов, mTLS)
openssl req -newkey rsa:4096 -nodes -keyout client-key.pem -out client-req.pem \
  -subj "/C=RU/ST=Moscow/L=Moscow/O=RailRepair/OU=IT/CN=*.railrepair.local/emailAddress=admin@railrepair.local"

openssl x509 -req -in client-req.pem -days 60 \
  -CA ca-cert.pem -CAkey ca-key.pem -CAcreateserial \
  -out client-cert.pem -extfile client-ext.cnf

echo "Client's signed certificate"
openssl x509 -in client-cert.pem -noout -text
