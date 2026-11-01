"""
CampusHub Serverless Microservices Handler (Pure Python Lambda - 100% Free Tier, No Docker/ECR)
Automates the 5 PRD Microservices + AWS Cognito JWT Auth + Private RDS PostgreSQL + One-Click Schema Migration

Microservices:
1. buy-sell         : Buy & Sell listings, categories, reserved/sold status
2. lost-found       : Lost & Found reports, categories, item reporting
3. academic-hub     : Departments, courses, academic materials, student feedback
4. placement-hub    : Company listings, hiring statistics, placement records
5. community-events : Campus services, events timeline, health checks & migration runner
"""

import os
import json
import logging
import socket
import ssl
import hashlib
import hmac
import base64
import secrets
import struct
import traceback
import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)


# ==============================================================================
# Pure Python PostgreSQL Client (Zero Dependencies, TLS 1.2+, SCRAM/MD5 Auth)
# ==============================================================================

class SimplePgClient:
    def __init__(self, host, port, user, password, database):
        self.host = host
        self.port = int(port)
        self.user = user
        self.password = password
        self.database = database
        self.sock = None

    def _recv_exact(self, n):
        data = bytearray()
        while len(data) < n:
            chunk = self.sock.recv(n - len(data))
            if not chunk:
                raise ConnectionError("Connection closed unexpectedly by PostgreSQL server")
            data.extend(chunk)
        return bytes(data)

    def _recv_msg(self):
        m_type = self._recv_exact(1)
        m_len = struct.unpack("!I", self._recv_exact(4))[0]
        payload = self._recv_exact(m_len - 4) if m_len > 4 else b""
        return m_type, payload

    def _send_msg(self, m_type, payload):
        self.sock.sendall(m_type + struct.pack("!I", len(payload) + 4) + payload)

    def _parse_error(self, payload):
        fields = {}
        i = 0
        while i < len(payload):
            code = payload[i:i+1]
            if code in (b"\x00", b""):
                break
            i += 1
            end = payload.find(b"\x00", i)
            if end == -1:
                break
            val = payload[i:end].decode("utf-8", errors="replace")
            fields[code.decode("ascii", errors="replace")] = val
            i = end + 1
        return fields

    def connect(self):
        logger.info(f"Connecting to PostgreSQL at {self.host}:{self.port} (database: {self.database}, user: {self.user})...")
        raw_sock = socket.create_connection((self.host, self.port), timeout=20)

        # 1. SSL Request (RDS PostgreSQL enforces TLS when rds.force_ssl = 1)
        raw_sock.sendall(struct.pack("!II", 8, 80877103))
        ssl_resp = raw_sock.recv(1)
        if ssl_resp == b"S":
            ctx = ssl.create_default_context()
            ctx.check_hostname = False
            ctx.verify_mode = ssl.CERT_NONE
            self.sock = ctx.wrap_socket(raw_sock)
        else:
            self.sock = raw_sock

        # 2. Startup Message (Protocol 3.0)
        user_bytes = self.user.encode("utf-8")
        db_bytes = self.database.encode("utf-8")
        body = (
            struct.pack("!I", 196608)
            + b"user\x00" + user_bytes + b"\x00"
            + b"database\x00" + db_bytes + b"\x00\x00"
        )
        self.sock.sendall(struct.pack("!I", len(body) + 4) + body)

        # 3. Authentication Handshake (SCRAM-SHA-256 / MD5 / Cleartext)
        client_nonce = secrets.token_hex(16)
        client_first_bare = f"n={self.user},r={client_nonce}"

        while True:
            m_type, payload = self._recv_msg()
            if m_type == b"E":
                err = self._parse_error(payload)
                raise ConnectionError(f"PostgreSQL Auth Error: {err.get('M', 'Unknown error')} (Code: {err.get('C', '')})")

            elif m_type == b"R":
                auth_type = struct.unpack("!I", payload[:4])[0]
                if auth_type == 0:
                    pass  # Auth OK
                elif auth_type == 3:  # Cleartext
                    p_body = self.password.encode("utf-8") + b"\x00"
                    self._send_msg(b"p", p_body)
                elif auth_type == 5:  # MD5
                    salt = payload[4:8]
                    h1 = hashlib.md5(self.password.encode("utf-8") + self.user.encode("utf-8")).hexdigest()
                    h2 = hashlib.md5(h1.encode("ascii") + salt).hexdigest()
                    p_body = b"md5" + h2.encode("ascii") + b"\x00"
                    self._send_msg(b"p", p_body)
                elif auth_type == 10:  # SASL (SCRAM-SHA-256)
                    mechanism = b"SCRAM-SHA-256\x00"
                    c_first = f"n,,{client_first_bare}".encode("utf-8")
                    msg = mechanism + struct.pack("!I", len(c_first)) + c_first
                    self._send_msg(b"p", msg)
                elif auth_type == 11:  # SASL Continue
                    server_first = payload[4:].decode("utf-8")
                    params = dict(part.split("=", 1) for part in server_first.split(",") if "=" in part)
                    server_nonce = params["r"]
                    salt = base64.b64decode(params["s"])
                    iterations = int(params["i"])

                    client_final_without_proof = f"c=biws,r={server_nonce}"
                    auth_message = f"{client_first_bare},{server_first},{client_final_without_proof}".encode("utf-8")
                    salted_password = hashlib.pbkdf2_hmac("sha256", self.password.encode("utf-8"), salt, iterations)
                    client_key = hmac.new(salted_password, b"Client Key", "sha256").digest()
                    stored_key = hashlib.sha256(client_key).digest()
                    client_signature = hmac.new(stored_key, auth_message, "sha256").digest()
                    client_proof = bytes(a ^ b for a, b in zip(client_key, client_signature))
                    client_final = f"{client_final_without_proof},p={base64.b64encode(client_proof).decode('ascii')}".encode("utf-8")
                    self._send_msg(b"p", client_final)
                elif auth_type == 12:  # SASL Final
                    pass

            elif m_type == b"Z":  # ReadyForQuery
                break

    def execute(self, sql_query):
        """Execute one or more SQL statements and return resulting rows as list of dicts/lists."""
        self._send_msg(b"Q", sql_query.encode("utf-8") + b"\x00")
        col_names = []
        rows = []
        errors = []

        while True:
            m_type, payload = self._recv_msg()
            if m_type == b"T":  # RowDescription
                num_fields = struct.unpack("!H", payload[:2])[0]
                col_names = []
                idx = 2
                for _ in range(num_fields):
                    null_pos = payload.find(b"\x00", idx)
                    col_name = payload[idx:null_pos].decode("utf-8", errors="replace")
                    col_names.append(col_name)
                    idx = null_pos + 1 + 18  # 18 bytes of type/mod/format metadata
            elif m_type == b"D":  # DataRow
                num_cols = struct.unpack("!H", payload[:2])[0]
                row = []
                idx = 2
                for _ in range(num_cols):
                    col_len = struct.unpack("!i", payload[idx:idx+4])[0]
                    idx += 4
                    if col_len == -1:
                        row.append(None)
                    else:
                        val = payload[idx:idx+col_len].decode("utf-8", errors="replace")
                        row.append(val)
                        idx += col_len
                if col_names and len(col_names) == len(row):
                    rows.append(dict(zip(col_names, row)))
                else:
                    rows.append(row)
            elif m_type == b"E":  # ErrorResponse
                err = self._parse_error(payload)
                errors.append(f"{err.get('M', 'Query error')} (Code: {err.get('C', '')})")
            elif m_type == b"Z":  # ReadyForQuery
                break

        if errors:
            raise RuntimeError("PostgreSQL Error: " + "; ".join(errors))
        return rows

    def close(self):
        if self.sock:
            try:
                self.sock.sendall(b"X\x00\x00\x00\x04")
                self.sock.close()
            except Exception:
                pass
            self.sock = None


# ==============================================================================
# Security: Retrieve Password Securely from AWS SSM Parameter Store via VPC Endpoint
# ==============================================================================

def get_db_credentials():
    """
    Securely fetches the master database password from AWS Systems Manager Parameter Store.
    Traffic flows over AWS PrivateLink (SSM VPC Interface Endpoint) without internet traversal.
    """
    ssm_param_name = os.environ.get("DB_PASSWORD_SSM_PARAM", "/campushub/dev/db/password")
    region = os.environ.get("AWS_REGION", "ap-south-1")
    logger.info(f"Securely fetching DB password from SSM Parameter Store: {ssm_param_name} in {region}")
    ssm = boto3.client("ssm", region_name=region)
    resp = ssm.get_parameter(Name=ssm_param_name, WithDecryption=True)
    return resp["Parameter"]["Value"]


def get_db_client():
    return SimplePgClient(
        host=os.environ.get("DB_HOST"),
        port=os.environ.get("DB_PORT", "5432"),
        user=os.environ.get("DB_USER", "campushub"),
        password=get_db_credentials(),
        database=os.environ.get("DB_NAME", "campushub"),
    )


# ==============================================================================
# Authentication & RBAC Helper (AWS Cognito JWT Claims)
# ==============================================================================

def extract_user(event):
    """
    Extracts verified user claims from API Gateway Cognito JWT Authorizer.
    Enforces 4-role permission model: Guest, Signed-in, Moderator, Administrator.
    """
    claims = event.get("requestContext", {}).get("authorizer", {}).get("jwt", {}).get("claims", {})
    if not claims:
        return {"is_authenticated": False, "role": "guest", "email": None, "sub": None, "groups": []}

    raw_groups = claims.get("cognito:groups", [])
    if isinstance(raw_groups, str):
        groups = [g.strip() for g in raw_groups.strip("[]").split(",") if g.strip()]
    elif isinstance(raw_groups, list):
        groups = raw_groups
    else:
        groups = []

    role = "user"
    if "Admin" in groups:
        role = "admin"
    elif "Moderator" in groups:
        role = "moderator"

    return {
        "is_authenticated": True,
        "role": role,
        "email": claims.get("email"),
        "sub": claims.get("sub"),
        "name": claims.get("name", claims.get("email", "").split("@")[0]),
        "groups": groups,
    }


def api_response(status_code, body):
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Headers": "Content-Type,Authorization,X-Amz-Date,X-Api-Key",
            "Access-Control-Allow-Methods": "GET,POST,PUT,PATCH,DELETE,OPTIONS",
        },
        "body": json.dumps(body, indent=2),
    }


# ==============================================================================
# Database Schema Initialization (One-Click Migration Runner)
# ==============================================================================

def run_migration():
    """Initializes RDS PostgreSQL tables and reference data using pure Python."""
    base_dir = os.path.dirname(__file__)
    schema_path = os.path.join(base_dir, "schema.sql")
    ref_data_path = os.path.join(base_dir, "reference-data.sql")

    with open(schema_path, "r", encoding="utf-8") as f:
        schema_sql = f.read()

    ref_sql = ""
    if os.path.exists(ref_data_path):
        with open(ref_data_path, "r", encoding="utf-8") as f:
            ref_sql = f.read()

    client = get_db_client()
    client.connect()
    try:
        logger.info("Executing schema.sql on RDS PostgreSQL...")
        client.execute(schema_sql)

        if ref_sql:
            logger.info("Executing reference-data.sql on RDS PostgreSQL...")
            client.execute(ref_sql)

        # Query created tables for verification
        tables_res = client.execute("SELECT tablename FROM pg_tables WHERE schemaname = 'public' ORDER BY tablename;")
        table_names = [t["tablename"] if isinstance(t, dict) else t[0] for t in tables_res]

        count_res = client.execute("SELECT count(*) as cnt FROM campus_services;")
        svc_cnt = int(count_res[0]["cnt"] if isinstance(count_res[0], dict) else count_res[0][0]) if count_res else 0

        return {
            "status": "success",
            "message": "RDS PostgreSQL schema and reference data successfully initialized!",
            "tables_count": len(table_names),
            "tables": table_names,
            "campus_services_count": svc_cnt,
        }
    finally:
        client.close()


# ==============================================================================
# Microservice Module Handlers (PRD Core Features)
# ==============================================================================

def handle_buy_sell(event, client, user):
    """Buy & Sell Module (FR-4, FR-5, FR-6)"""
    path = event.get("rawPath", event.get("path", ""))
    method = event.get("requestContext", {}).get("http", {}).get("method", "GET")

    if path.endswith("/categories"):
        rows = client.execute("SELECT id, name FROM bs_categories ORDER BY name;")
        return api_response(200, {"categories": rows})

    if method == "POST":
        if not user["is_authenticated"]:
            return api_response(401, {"error": "Authentication required to post listings (Cognito JWT required)"})
        body = json.loads(event.get("body") or "{}")
        title = body.get("title", "").replace("'", "''")
        desc = body.get("description", "").replace("'", "''")
        price = float(body.get("price", 0.0))
        cat_id = body.get("category_id")

        cat_sql = f"'{cat_id}'" if cat_id else "(SELECT id FROM bs_categories LIMIT 1)"
        sql = f"""
            INSERT INTO listings (seller_id, category_id, title, description, price, status)
            VALUES ((SELECT id FROM users WHERE email = '{user['email']}' LIMIT 1), {cat_sql}, '{title}', '{desc}', {price}, 'available')
            RETURNING id, title, price, status;
        """
        res = client.execute(sql)
        return api_response(201, {"message": "Listing created successfully", "listing": res[0] if res else {}})

    # Default: GET listings (public read for guests, filterable)
    rows = client.execute("""
        SELECT l.id, l.title, l.price, l.status, l.created_at, c.name as category
        FROM listings l
        LEFT JOIN bs_categories c ON l.category_id = c.id
        ORDER BY l.created_at DESC
        LIMIT 50;
    """)
    return api_response(200, {"service": "buy-sell", "items": rows})


def handle_lost_found(event, client, user):
    """Lost & Found Module (FR-7, FR-8, FR-9)"""
    path = event.get("rawPath", event.get("path", ""))
    method = event.get("requestContext", {}).get("http", {}).get("method", "GET")

    if path.endswith("/categories"):
        rows = client.execute("SELECT id, name FROM lf_categories ORDER BY name;")
        return api_response(200, {"categories": rows})

    if "found" in path:
        if method == "POST":
            if not user["is_authenticated"]:
                return api_response(401, {"error": "Authentication required to file found reports"})
            body = json.loads(event.get("body") or "{}")
            desc = body.get("description", "").replace("'", "''")
            loc = body.get("location_found", "").replace("'", "''")
            sql = f"""
                INSERT INTO found_reports (finder_id, description, location_found)
                VALUES ((SELECT id FROM users WHERE email = '{user['email']}' LIMIT 1), '{desc}', '{loc}')
                RETURNING id, description, status;
            """
            res = client.execute(sql)
            return api_response(201, {"message": "Found report filed successfully", "report": res[0] if res else {}})
        rows = client.execute("SELECT id, description, location_found, status, created_at FROM found_reports ORDER BY created_at DESC LIMIT 50;")
        return api_response(200, {"service": "lost-found", "type": "found_reports", "reports": rows})

    # Lost reports flow
    if method == "POST":
        if not user["is_authenticated"]:
            return api_response(401, {"error": "Authentication required to file lost reports"})
        body = json.loads(event.get("body") or "{}")
        desc = body.get("description", "").replace("'", "''")
        loc = body.get("location_lost", "").replace("'", "''")
        sql = f"""
            INSERT INTO lost_reports (reporter_id, description, location_lost)
            VALUES ((SELECT id FROM users WHERE email = '{user['email']}' LIMIT 1), '{desc}', '{loc}')
            RETURNING id, description, status;
        """
        res = client.execute(sql)
        return api_response(201, {"message": "Lost report filed successfully", "report": res[0] if res else {}})

    rows = client.execute("SELECT id, description, location_lost, status, created_at FROM lost_reports ORDER BY created_at DESC LIMIT 50;")
    return api_response(200, {"service": "lost-found", "type": "lost_reports", "reports": rows})


def handle_academic_hub(event, client, user):
    """Academic Help Module (FR-11, FR-12, FR-13)"""
    path = event.get("rawPath", event.get("path", ""))

    if "/departments" in path:
        rows = client.execute("SELECT id, name FROM departments ORDER BY name;")
        return api_response(200, {"departments": rows})

    if "/courses" in path:
        rows = client.execute("""
            SELECT c.id, c.code, c.name, d.name as department
            FROM courses c
            LEFT JOIN departments d ON c.department_id = d.id
            ORDER BY c.code;
        """)
        return api_response(200, {"courses": rows})

    return api_response(200, {"service": "academic-hub", "status": "active", "message": "CampusHub Academic Hub API"})


def handle_placement_hub(event, client, user):
    """Placement Hub Module (FR-15, FR-16, FR-17)"""
    rows = client.execute("SELECT id, name, description FROM companies ORDER BY name LIMIT 50;")
    return api_response(200, {
        "service": "placement-hub",
        "companies": rows,
        "summary": "Placement statistics and past recruitment records"
    })


def handle_community_events(event, client, user):
    """Community & Events Module (FR-18, FR-19, FR-20, FR-21)"""
    path = event.get("rawPath", event.get("path", ""))

    if "/services" in path or "/campus-services" in path:
        rows = client.execute("""
            SELECT id, name, description, category, url, phone, sort_order
            FROM campus_services
            ORDER BY sort_order;
        """)
        return api_response(200, {"campus_services": rows})

    rows = client.execute("""
        SELECT id, title, description, start_time, end_time, location
        FROM events
        ORDER BY start_time DESC
        LIMIT 50;
    """)
    return api_response(200, {"service": "community-events", "events": rows})


# ==============================================================================
# Main AWS Lambda Handler
# ==============================================================================

def lambda_handler(event, context):
    raw_path = event.get("rawPath", event.get("path", "/"))
    method = event.get("requestContext", {}).get("http", {}).get("method", "GET")
    service_name = os.environ.get("SERVICE_NAME", "community-events")

    # 1. Database Migration Action
    is_migrate = (
        event.get("action") == "migrate"
        or raw_path.rstrip("/").endswith("/migrate")
        or (event.get("queryStringParameters") or {}).get("migrate") == "true"
    )
    if is_migrate:
        try:
            result = run_migration()
            return api_response(200, result)
        except Exception as e:
            logger.error("Migration failed: " + traceback.format_exc())
            return api_response(500, {"status": "error", "error": str(e), "traceback": traceback.format_exc()})

    # 2. Extract Authenticated User Context (Cognito JWT claims validated by API Gateway)
    user = extract_user(event)

    # 3. Simple Health Check
    if raw_path in ("/", "/health", f"/api/{service_name}/health"):
        return api_response(200, {
            "service": service_name,
            "status": "healthy",
            "environment": os.environ.get("ENVIRONMENT", "dev"),
            "authenticated": user["is_authenticated"],
            "user": user["email"],
            "role": user["role"],
        })

    # 4. Dispatch to Specific Microservice with RDS Connection
    client = get_db_client()
    try:
        client.connect()

        if service_name == "buy-sell" or "/buy-sell" in raw_path:
            return handle_buy_sell(event, client, user)
        elif service_name == "lost-found" or "/lost-found" in raw_path:
            return handle_lost_found(event, client, user)
        elif service_name == "academic-hub" or "/academic" in raw_path:
            return handle_academic_hub(event, client, user)
        elif service_name == "placement-hub" or "/placement" in raw_path:
            return handle_placement_hub(event, client, user)
        else:
            return handle_community_events(event, client, user)

    except Exception as e:
        logger.error(f"Error handling request in {service_name}: " + traceback.format_exc())
        return api_response(500, {
            "service": service_name,
            "error": str(e),
            "traceback": traceback.format_exc(),
        })
    finally:
        client.close()
