# Avoqado Windows Service

## 1. Short Description

This project is a Windows service that acts as a real-time synchronization bridge between a local Point-of-Sale (POS) system and the central Avoqado platform. It continuously monitors the POS database for changes to orders, items, and shifts, publishing these events to a RabbitMQ message broker. It also listens for commands sent from the Avoqado platform (e.g., create an order) and executes them on the local POS system. This ensures seamless data consistency and enables remote management capabilities.

## 2. Tech Stack

- **Language**: TypeScript
- **Platform**: Node.js
- **Database**: Microsoft SQL Server
- **Messaging**: RabbitMQ
- **Core Libraries**:
  - `node-windows`: To run the application as a native Windows service.
  - `mssql`: Microsoft SQL Server driver for Node.js.
  - `amqplib`: RabbitMQ client library.
  - `winston`: For robust and configurable logging.
  - `dotenv`: For managing environment variables.
- **Tooling**:
  - `pkg`: For packaging the application into a single executable file.
  - `prettier`: For code formatting.

## 3. Key Features

- **Bidirectional Data Sync**: 
  - **Producer**: Polls the POS database for changes and publishes them to the central system.
  - **Commander**: Listens for incoming commands from the central system and executes them on the POS.
- **Real-time Event Publishing**: Captures and dispatches events for orders, order items, and shifts as they occur.
- **Efficient Order Updates**: Implements a debouncing mechanism to batch multiple rapid updates to a single order into one message, reducing network traffic.
- **POS Adapter Architecture**: Uses a flexible adapter pattern (`SoftRestaurant11Adapter`) to decouple the core logic from specific POS implementations.
- **Windows Service Integration**: Can be installed, uninstalled, and run as a background Windows service for reliability.
- **Health Monitoring**: Sends regular heartbeats to the central system to indicate its operational status.

## 4. Project Structure

A high-level overview of the most important directories and files:

```
.env.example        # Template for environment variables
package.json        # Project dependencies and scripts
src/
├── main.ts           # Entry point for installing/uninstalling the Windows service
├── service.ts        # Main application entry point that starts the service
├── config.ts         # Loads and manages application configuration
├── core/             # Core modules for DB, RabbitMQ, and logging
│   ├── db.ts
│   ├── logger.ts
│   └── rabbitmq.ts
├── components/       # High-level application logic
│   ├── producer.ts   # Polls the DB and publishes changes
│   └── commander.ts  # Listens for and executes incoming commands
└── adapters/         # Adapters for specific POS systems
    └── SoftRestaurant11Adapter.ts
```

## 5. Getting Started

### Prerequisites

- Node.js (v18 or higher recommended)
- NPM (included with Node.js)
- Access to a Microsoft SQL Server instance
- Access to a RabbitMQ server

### Installation & Setup

1.  **Clone the repository**:
    ```bash
    git clone <repository-url>
    cd avoqado-windows-service
    ```

2.  **Install dependencies**:
    ```bash
    npm install
    ```

3.  **Set up environment variables**:
    - Copy the `.env.example` file to a new file named `.env`.
    - Fill in the required values for the database, RabbitMQ, and venue configuration in the `.env` file.

## 6. Usage

### Development

To run the service in development mode with hot-reloading:

```bash
npm run dev
```

### Production Build

1.  **Compile TypeScript to JavaScript**:
    ```bash
    npm run build
    ```

2.  **Run the compiled code**:
    ```bash
    npm start
    ```

### As a Windows Service

To install and manage the application as a Windows service, you must run the following commands in an **administrator terminal**:

- **Install the service**:
  ```bash
  npm run svc:install
  ```

- **Uninstall the service**:
  ```bash
  npm run svc:uninstall
  ```

After installation, the service will start automatically with Windows.

### Package as an Executable

To package the entire application into a single `.exe` file:

```bash
npm run package
```

This will generate `AvoqadoSyncService.exe` in the root directory.

## 7. Running Tests

This project does not currently have an automated test suite configured. The available scripts for checking code quality are:

- **Check formatting**:
  ```bash
  npm run check-format
  ```

- **Apply formatting**:
  ```bash
  npm run format
  ```

## 8. License

This project is currently unlicensed.