# 🔐 secure-microservices-demo
Secure application based on microservice architecture

<!-- Блок переключения языков -->
<div align="center">

[Русский](#-на-русском) | [English](#-english)

</div>

---

## 🇷🇺 

### 📋 Описание проекта
Данный проект выполнен в рамках курсового проекта по информационной безопасности. Цель работы — спроектировать и реализовать рабочее безопасное приложение с использованием микросервисной архитектуры.

### 🧱 Архитектура проекта
| Компонент             | Назначение                                                                 |
|-----------------------|-----------------------------------------------------------------------------|
| Keycloak              | Сервер для централизованной аутентификации и авторизации пользователей    |
| Auth Service          | Собственный микросервис для обработки токенов и интеграции с Keycloak     |
| User Service          | Микросервис для управления профильными данными пользователей              |
| Central gRPC Server   | Центральный координирующий сервис для обработки запросов внутренних сервисов |
| API Gateway           | Единая точка входа для внешних клиентов, трансляция HTTP в gRPC           |
| Prometheus            | Сбор метрик и мониторинг работоспособности всех компонентов системы        |
| PostgreSQL            | Реляционная база данных для постоянного хранения данных                    |
| Redis                 | Кэширование часто запрашиваемых данных для ускорения ответов              |
| RabbitMQ/Kafka        | Брокер сообщений для асинхронного взаимодействия между сервисами          |

### 🚀 Быстрый старт

#### Предварительные требования
- Установленные Docker и Docker Compose на вашем устройстве

#### Шаги для запуска
1. Клонируйте репозиторий:
```bash
git clone https://github.com/keivik/secure-microservices.git 
cd secure-microservices
```

Запустите все сервисы через Docker Compose:
```bash
docker compose up --build
```
После запуска доступны следующие интерфейсы:
| Сервис | Локальный адрес | |--------------|---------------------------| | API Gateway | http://localhost:8000 | | Keycloak Admin | http://localhost:8080 | | Prometheus | http://localhost:9091 |

### 🛡️ Безопасность в проекте

#### Реализованы следующие практики безопасной разработки для микросервисов:

* Централизованная аутентификация через OpenID Connect
* Аутентификация сервисов друг друга через mTLS
* Хранение чувствительных данных в переменных окружения
* Использование SSL/TLS для всех внутренних и внешних соединений
* Сбор и мониторинг метрик безопасности
### 📄 Лицензия
Данный проект распространяется под лицензией MIT — вы можете свободно использовать его для учебных и коммерческих целей.

--- 

</div>

--- 

## ENG 
### 📋 Project Description
This project is developed as a course project for information security program. The main goal is to design and implement a working secure application based on microservice architecture.

### 🧱 Project Architecture
| Component             | 	Purpose                                                                 |
|-----------------------|-----------------------------------------------------------------------------|
| Keycloak              | Central authentication and authorization server for users    |
| Auth Service          | Custom microservice for token processing and Keycloak integration     |
| User Service          | Microservice for managing user profile data           |
| Central gRPC Server   | Central coordinating service for processing requests from internal services |
| API Gateway           | 	Single entry point for external clients, translates HTTP to gRPC       |
| Prometheus            | Metrics collection and health monitoring for all system components       |
| PostgreSQL            | Relational database for persistent data storage                    |
| Redis                 | 	Caching of frequently requested data to speed up responses             |
| RabbitMQ/Kafka        | Message broker for asynchronous inter-service communication      |

### 🚀 Quick Start

#### Prerequisites
* Docker and Docker Compose installed on your machine

#### Steps to run
1. Clone the repository:
``` bash
git clone https://github.com/keivik3/secure-microservices.git 
cd secure-microservices-demo
```

2. Start all services with Docker Compose:
``` bash
docker compose up --build
```

#### After startup, the following interfaces are available:
| Service | Local address | |---------------|---------------------------| | API Gateway | http://localhost:8000 | | Keycloak Admin | http://localhost:8080 | | Prometheus | http://localhost:9091 |

### 🛡️ Security implementation

#### The following secure development practices for microservices are implemented:

* Centralized authentication via OpenID Connect
* Service-to-service authentication via mTLS
* Sensitive data stored in environment variables
* SSL/TLS encryption for all internal and external connections
* Security metrics collection and monitoring

### 📄 License
This project is licensed under the MIT License - you are free to use it for educational and commercial purposes.


---
