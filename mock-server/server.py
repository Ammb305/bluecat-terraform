#!/usr/bin/env python3
"""
Mock BlueCat API Server for Testing
This server simulates BlueCat's REST API endpoints for testing the Terraform module locally.
"""

from flask import Flask, request, jsonify, make_response
import base64
import json
import uuid
from datetime import datetime, timedelta
import threading
import time

app = Flask(__name__)

# In-memory storage for testing
tokens = {}
zones = {
    "queue.core.windows.net": {"id": 100001, "name": "queue.core.windows.net"},
    "privatelink.queue.core.windows.net": {"id": 100002, "name": "privatelink.queue.core.windows.net"},
    "example.com": {"id": 100003, "name": "example.com"}
}
records = {}
record_counter = 200000

def cleanup_expired_tokens():
    """Clean up expired tokens every minute"""
    while True:
        current_time = datetime.now()
        expired_tokens = [token for token, data in tokens.items() 
                         if data['expires'] < current_time]
        for token in expired_tokens:
            del tokens[token]
        time.sleep(60)

# Start token cleanup thread
cleanup_thread = threading.Thread(target=cleanup_expired_tokens, daemon=True)
cleanup_thread.start()

def require_auth(f):
    """Decorator to require valid authentication token"""
    def decorated_function(*args, **kwargs):
        auth_header = request.headers.get('Authorization', '')
        
        # Handle both BAMAuthToken and Bearer token formats
        token = None
        if auth_header.startswith('BAMAuthToken: '):
            token = auth_header.replace('BAMAuthToken: ', '')
        elif auth_header.startswith('Bearer '):
            token = auth_header.replace('Bearer ', '')
        else:
            return jsonify({"error": "Invalid authentication header"}), 401
        
        if token not in tokens:
            return jsonify({"error": "Invalid or expired token"}), 401
        
        if tokens[token]['expires'] < datetime.now():
            del tokens[token]
            return jsonify({"error": "Token expired"}), 401
        
        return f(*args, **kwargs)
    
    # Fix the function name to avoid conflicts
    decorated_function.__name__ = f.__name__
    return decorated_function

@app.route('/Services/REST/v1/login', methods=['GET'])
def login():
    """Authenticate and return a token"""
    auth_header = request.headers.get('Authorization', '')
    
    if not auth_header.startswith('Basic '):
        return jsonify({"error": "Basic authentication required"}), 401
    
    try:
        # Decode base64 credentials
        encoded_creds = auth_header.replace('Basic ', '')
        decoded_creds = base64.b64decode(encoded_creds).decode('utf-8')
        username, password = decoded_creds.split(':', 1)
        
        # Simple authentication (accept any non-empty credentials)
        if not username or not password:
            return jsonify({"error": "Invalid credentials"}), 401
        
        # Generate token
        token = str(uuid.uuid4())
        expires = datetime.now() + timedelta(hours=1)
        
        tokens[token] = {
            'username': username,
            'expires': expires
        }
        
        return jsonify({
            "token": token,
            "expires": expires.isoformat()
        })
        
    except Exception as e:
        return jsonify({"error": "Authentication failed"}), 401

@app.route('/Services/REST/v1/logout', methods=['GET'])
@require_auth
def logout():
    """Logout and invalidate token"""
    auth_header = request.headers.get('Authorization', '')
    token = auth_header.replace('BAMAuthToken: ', '')
    
    if token in tokens:
        del tokens[token]
    
    return jsonify({"message": "Logged out successfully"})

@app.route('/Services/REST/v1/getZonesByHint', methods=['GET'])
@require_auth
def get_zones_by_hint():
    """Get zone information by hint"""
    hint = request.args.get('hint', '')
    
    matching_zones = []
    for zone_name, zone_data in zones.items():
        if hint.lower() in zone_name.lower():
            matching_zones.append(zone_data)
    
    return jsonify(matching_zones)

@app.route('/Services/REST/v1/getHostRecordsByHint', methods=['GET'])
@require_auth
def get_host_records_by_hint():
    """Get host records by hint"""
    hint = request.args.get('hint', '')
    
    matching_records = []
    for record_id, record_data in records.items():
        fqdn = f"{record_data['name']}.{record_data['zone']}"
        if hint.lower() in fqdn.lower():
            matching_records.append({
                "id": record_id,
                **record_data
            })
    
    return jsonify(matching_records)

@app.route('/Services/REST/v1/addHostRecord', methods=['POST'])
@require_auth
def add_host_record():
    """Create a new host record"""
    global record_counter
    
    try:
        data = request.get_json()
        
        # Validate required fields
        required_fields = ['name', 'type', 'rdata', 'parentId']
        for field in required_fields:
            if field not in data:
                return jsonify({"error": f"Missing required field: {field}"}), 400
        
        # Find the zone
        zone_name = None
        for zname, zdata in zones.items():
            if zdata['id'] == data['parentId']:
                zone_name = zname
                break
        
        if not zone_name:
            return jsonify({"error": "Invalid zone ID"}), 400
        
        # Create record
        record_counter += 1
        record_id = record_counter
        
        record_data = {
            "name": data['name'],
            "type": data['type'],
            "rdata": data['rdata'],
            "ttl": data.get('ttl', 3600),
            "zone": zone_name,
            "parentId": data['parentId'],
            "created": datetime.now().isoformat()
        }
        
        records[record_id] = record_data
        
        return jsonify({"id": record_id, "message": "Record created successfully"}), 201
        
    except Exception as e:
        return jsonify({"error": str(e)}), 400

@app.route('/Services/REST/v1/update', methods=['PUT'])
@require_auth
def update_record():
    """Update an existing record"""
    try:
        data = request.get_json()
        
        if 'id' not in data:
            return jsonify({"error": "Record ID is required"}), 400
        
        record_id = data['id']
        
        if record_id not in records:
            return jsonify({"error": "Record not found"}), 404
        
        # Update record
        record_data = records[record_id]
        
        if 'name' in data:
            record_data['name'] = data['name']
        if 'type' in data:
            record_data['type'] = data['type']
        if 'rdata' in data:
            record_data['rdata'] = data['rdata']
        if 'ttl' in data:
            record_data['ttl'] = data['ttl']
        
        record_data['updated'] = datetime.now().isoformat()
        
        return jsonify({"message": "Record updated successfully"})
        
    except Exception as e:
        return jsonify({"error": str(e)}), 400

@app.route('/Services/REST/v1/delete', methods=['DELETE'])
@require_auth
def delete_record():
    """Delete a record"""
    object_id = request.args.get('objectId')
    
    if not object_id:
        return jsonify({"error": "objectId parameter is required"}), 400
    
    try:
        object_id = int(object_id)
    except ValueError:
        return jsonify({"error": "Invalid objectId"}), 400
    
    if object_id not in records:
        return jsonify({"error": "Record not found"}), 404
    
    del records[object_id]
    return jsonify({"message": "Record deleted successfully"})

@app.route('/Services/REST/v1/quickDeploy', methods=['POST'])
@require_auth
def quick_deploy():
    """Deploy configuration changes"""
    try:
        data = request.get_json()
        
        if 'entityId' not in data:
            return jsonify({"error": "entityId is required"}), 400
        
        # Simulate deployment
        return jsonify({
            "message": "Configuration deployed successfully",
            "deploymentId": str(uuid.uuid4())
        })
        
    except Exception as e:
        return jsonify({"error": str(e)}), 400

#
# V2 API Endpoints
#

@app.route('/api/v2/sessions', methods=['POST'])
def login_v2():
    """Authenticate and return a token for v2"""
    try:
        # Handle both JSON and Basic Auth
        data = request.get_json()
        
        if data and 'username' in data and 'password' in data:
            # JSON authentication
            username = data['username']
            password = data['password']
        else:
            # Basic authentication fallback
            auth_header = request.headers.get('Authorization', '')
            if not auth_header.startswith('Basic '):
                return jsonify({"error": "Authentication required"}), 401
            
            encoded_creds = auth_header.replace('Basic ', '')
            decoded_creds = base64.b64decode(encoded_creds).decode('utf-8')
            username, password = decoded_creds.split(':', 1)
        
        # Simple authentication (accept any non-empty credentials)
        if not username or not password:
            return jsonify({"error": "Invalid credentials"}), 401
        
        # Generate token
        token = str(uuid.uuid4())
        expires = datetime.now() + timedelta(hours=1)
        
        tokens[token] = {
            'username': username,
            'expires': expires
        }
        
        # Return token in response body for script compatibility
        return jsonify({
            "token": token,
            "id": "session",
            "type": "session", 
            "username": username,
            "expires": expires.isoformat()
        })
        
    except Exception as e:
        return jsonify({"error": f"Authentication failed: {e}"}), 401

# --- V2 REST API Endpoints (Simple Pattern) ---

@app.route('/api/v2/zones', methods=['GET'])
@require_auth
def get_zones_v2():
    """Get zones by name filter (v2 API)"""
    zone_name = request.args.get('name', '')
    
    if zone_name:
        # Return specific zone by exact name match
        for zname, zdata in zones.items():
            if zname == zone_name:
                return jsonify([{
                    "id": zdata['id'],
                    "name": zname,
                    "type": zdata.get('type', 'Zone'),
                    "properties": zdata.get('properties', '')
                }])
        return jsonify([])  # Zone not found
    else:
        # Return all zones
        zone_list = []
        for zname, zdata in zones.items():
            zone_list.append({
                "id": zdata['id'],
                "name": zname,
                "type": zdata.get('type', 'Zone'),
                "properties": zdata.get('properties', '')
            })
        return jsonify(zone_list)

@app.route('/api/v2/records', methods=['GET'])
@require_auth
def get_records_v2():
    """Get records by zone, name, and type (v2 API)"""
    zone_id = request.args.get('zone')
    record_name = request.args.get('name')
    record_type = request.args.get('type')
    
    matching_records = []
    for record_id, record_data in records.items():
        # Check zone match
        if zone_id and str(record_data.get('parentId', '')) != str(zone_id):
            continue
        
        # Check name match (FQDN)
        if record_name:
            fqdn = f"{record_data['name']}.{record_data['zone']}"
            if fqdn != record_name:
                continue
        
        # Check type match
        if record_type and record_data.get('type', '').upper() != record_type.upper():
            continue
        
        matching_records.append({
            "id": record_id,
            "name": f"{record_data['name']}.{record_data['zone']}",
            "type": record_data.get('type', 'HostRecord'),
            "rdata": record_data.get('rdata', ''),
            "ttl": record_data.get('ttl', 3600),
            "zoneId": record_data.get('parentId')
        })
    
    return jsonify(matching_records)

@app.route('/api/v2/records', methods=['POST'])
@require_auth
def create_record_v2():
    """Create a new DNS record (v2 API)"""
    global record_counter
    
    try:
        data = request.get_json()
        
        if not all(k in data for k in ['name', 'type', 'zoneId']):
            return jsonify({"error": "Missing required fields: name, type, zoneId"}), 400
        
        # Find zone name by ID
        zone_name = None
        for zname, zdata in zones.items():
            if zdata['id'] == data['zoneId']:
                zone_name = zname
                break
        
        if not zone_name:
            return jsonify({"error": "Invalid zone ID"}), 400
        
        # Extract record name from FQDN
        fqdn = data['name']
        if fqdn.endswith(f".{zone_name}"):
            record_name = fqdn[:-len(f".{zone_name}")]
        else:
            record_name = fqdn
        
        # Extract rdata based on record type and structure
        rdata_value = ""
        if 'rdata' in data:
            rdata_obj = data['rdata']
            if isinstance(rdata_obj, dict):
                # Handle structured rdata
                rdata_value = (rdata_obj.get('address') or 
                              rdata_obj.get('cname') or 
                              rdata_obj.get('text') or str(rdata_obj))
            else:
                rdata_value = str(rdata_obj)
        
        # Create record
        record_counter += 1
        record_id = record_counter
        
        record_data = {
            "name": record_name,
            "type": data['type'],
            "rdata": rdata_value,
            "ttl": data.get('ttl', 3600),
            "zone": zone_name,
            "parentId": data['zoneId'],
            "created": datetime.now().isoformat()
        }
        
        records[record_id] = record_data
        
        return jsonify({
            "id": record_id,
            "name": fqdn,
            "type": data['type'],
            "rdata": rdata_value,
            "ttl": record_data['ttl'],
            "zoneId": data['zoneId']
        }), 201
        
    except Exception as e:
        return jsonify({"error": str(e)}), 400

@app.route('/api/v2/records/<int:record_id>', methods=['PUT'])
@require_auth
def update_record_v2(record_id):
    """Update an existing DNS record (v2 API)"""
    if record_id not in records:
        return jsonify({"error": "Record not found"}), 404
    
    try:
        data = request.get_json()
        
        # Extract rdata based on record type and structure
        if 'rdata' in data:
            rdata_obj = data['rdata']
            if isinstance(rdata_obj, dict):
                rdata_value = (rdata_obj.get('address') or 
                              rdata_obj.get('cname') or 
                              rdata_obj.get('text') or str(rdata_obj))
            else:
                rdata_value = str(rdata_obj)
            records[record_id]['rdata'] = rdata_value
        
        # Update other fields
        if 'ttl' in data:
            records[record_id]['ttl'] = data['ttl']
        if 'type' in data:
            records[record_id]['type'] = data['type']
        
        records[record_id]['updated'] = datetime.now().isoformat()
        
        # Build response
        fqdn = f"{records[record_id]['name']}.{records[record_id]['zone']}"
        
        return jsonify({
            "id": record_id,
            "name": fqdn,
            "type": records[record_id]['type'],
            "rdata": records[record_id]['rdata'],
            "ttl": records[record_id]['ttl'],
            "zoneId": records[record_id]['parentId']
        })
        
    except Exception as e:
        return jsonify({"error": str(e)}), 400

@app.route('/api/v2/records/<int:record_id>', methods=['DELETE'])
@require_auth
def delete_record_v2(record_id):
    """Delete a DNS record (v2 API)"""
    if record_id not in records:
        return jsonify({"error": "Record not found"}), 404
    
    del records[record_id]
    return '', 204

@app.route('/api/v2/zones/<int:zone_id>/deploy', methods=['POST'])
@require_auth
def deploy_zone_v2(zone_id):
    """Deploy zone changes (v2 API)"""
    # Find zone by ID
    zone_found = False
    for zname, zdata in zones.items():
        if zdata['id'] == zone_id:
            zone_found = True
            break
    
    if not zone_found:
        return jsonify({"error": "Zone not found"}), 404
    
    return jsonify({
        "message": f"Zone {zone_id} deployed successfully",
        "deploymentId": str(uuid.uuid4()),
        "status": "completed"
    })

# --- Services/REST/v2 Aliases (for backward compatibility) ---

@app.route('/Services/REST/v2/sessions', methods=['POST'])
def login_services_rest_v2():
    """Alias for /api/v2/sessions"""
    return login_v2()

@app.route('/Services/REST/v2/zones', methods=['GET'])
@require_auth
def get_zones_services_rest_v2():
    """Alias for /api/v2/zones"""
    return get_zones_v2()

@app.route('/Services/REST/v2/records', methods=['GET'])
@require_auth
def get_records_services_rest_v2():
    """Alias for /api/v2/records"""
    return get_records_v2()

@app.route('/Services/REST/v2/records', methods=['POST'])
@require_auth
def create_record_services_rest_v2():
    """Alias for /api/v2/records"""
    return create_record_v2()

@app.route('/Services/REST/v2/records/<int:record_id>', methods=['PUT'])
@require_auth
def update_record_services_rest_v2(record_id):
    """Alias for /api/v2/records/{id}"""
    return update_record_v2(record_id)

@app.route('/Services/REST/v2/records/<int:record_id>', methods=['DELETE'])
@require_auth
def delete_record_services_rest_v2(record_id):
    """Alias for /api/v2/records/{id}"""
    return delete_record_v2(record_id)

@app.route('/Services/REST/v2/zones/<int:zone_id>/deploy', methods=['POST'])
@require_auth
def deploy_zone_services_rest_v2(zone_id):
    """Alias for /api/v2/zones/{id}/deploy"""
    return deploy_zone_v2(zone_id)

@app.route('/Services/REST/v2/sessions/<token>', methods=['DELETE'])
@require_auth
def delete_session_services_rest_v2(token):
    """Alias for /api/v2/sessions/{token}"""
    return delete_session_v2(token)

@app.route('/api/v2/getZonesByHint', methods=['GET'])
@require_auth
def get_zones_by_hint_v2():
    """Get zone information by hint (v2 API) - Legacy endpoint"""
    hint = request.args.get('hint', '')
    
    matching_zones = []
    for zone_name, zone_data in zones.items():
        if hint.lower() in zone_name.lower():
            matching_zones.append(zone_data)
    
    return jsonify(matching_zones)

@app.route('/api/v2/zones/<int:zone_id>/entities', methods=['GET'])
@require_auth
def get_zone_entities_v2(zone_id):
    """Get all entities for a given zone"""
    matching_records = []
    for record_id, record_data in records.items():
        if record_data.get('parentId') == zone_id:
            matching_records.append({
                "id": record_id,
                "name": record_data['name'],
                "type": record_data['type'],
                "properties": f"rdata={record_data.get('rdata', '')}|ttl={record_data.get('ttl', '')}"
            })
    return jsonify({"data": matching_records})

@app.route('/api/v2/zones/<int:zone_id>/entities', methods=['POST'])
@require_auth
def add_entity_v2(zone_id):
    """Create a new entity in a zone"""
    global record_counter
    try:
        data = request.get_json()
        
        if not all(k in data for k in ['name', 'type', 'properties']):
            return jsonify({"error": "Missing required fields"}), 400

        zone_name = next((zname for zname, zdata in zones.items() if zdata['id'] == zone_id), None)
        if not zone_name:
            return jsonify({"error": "Invalid zone ID"}), 400

        record_counter += 1
        record_id = record_counter
        
        props = dict(item.split("=") for item in data['properties'].split("|"))
        rdata = props.get('linkedRecordName') or props.get('addresses') or props.get('rdata', '').strip('\\"')

        record_data = {
            "name": data['name'],
            "type": data['type'],
            "rdata": rdata,
            "ttl": props.get('ttl', 3600),
            "zone": zone_name,
            "parentId": zone_id,
            "created": datetime.now().isoformat()
        }
        records[record_id] = record_data
        
        return jsonify({"id": record_id, "name": data['name'], "type": data['type']}), 201
    except Exception as e:
        return jsonify({"error": str(e)}), 400

@app.route('/api/v2/entities/<int:record_id>', methods=['PUT'])
@require_auth
def update_entity_v2(record_id):
    """Update an existing entity"""
    if record_id not in records:
        return jsonify({"error": "Record not found"}), 404
    
    try:
        data = request.get_json()
        props = dict(item.split("=") for item in data['properties'].split("|"))
        rdata = props.get('linkedRecordName') or props.get('addresses') or props.get('rdata', '').strip('\\"')

        records[record_id]['name'] = data.get('name', records[record_id]['name'])
        records[record_id]['rdata'] = rdata
        records[record_id]['ttl'] = props.get('ttl', records[record_id]['ttl'])
        records[record_id]['updated'] = datetime.now().isoformat()
        
        return jsonify(records[record_id])
    except Exception as e:
        return jsonify({"error": str(e)}), 400

@app.route('/api/v2/entities/<int:record_id>', methods=['DELETE'])
@require_auth
def delete_entity_v2(record_id):
    """Delete an entity"""
    if record_id not in records:
        return jsonify({"error": "Record not found"}), 404
    
    del records[record_id]
    return '', 204

@app.route('/api/v2/quickDeploy', methods=['POST'])
@require_auth
def quick_deploy_v2():
    """Deploy configuration changes (v2 API)"""
    try:
        data = request.get_json()
        
        if 'entityId' not in data:
            return jsonify({"error": "entityId is required"}), 400
        
        # Simulate deployment
        return jsonify({
            "message": "Configuration deployed successfully",
            "deploymentId": str(uuid.uuid4())
        })
        
    except Exception as e:
        return jsonify({"error": str(e)}), 400

@app.route('/api/v2/sessions/<token>', methods=['DELETE'])
@require_auth
def delete_session_v2(token):
    """Delete session/logout (v2 API)"""
    if token in tokens:
        del tokens[token]
    
    return '', 204

@app.route('/api/v2/logout', methods=['GET'])
@require_auth
def logout_v2():
    """Logout and invalidate token (v2 API) - Legacy endpoint"""
    auth_header = request.headers.get('Authorization', '')
    
    # Extract token from either format
    token = None
    if auth_header.startswith('BAMAuthToken: '):
        token = auth_header.replace('BAMAuthToken: ', '')
    elif auth_header.startswith('Bearer '):
        token = auth_header.replace('Bearer ', '')
    
    if token and token in tokens:
        del tokens[token]
    
    return jsonify({"message": "Logged out successfully"})

@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    return jsonify({
        "status": "healthy",
        "active_tokens": len(tokens),
        "total_records": len(records),
        "zones": len(zones)
    })

@app.route('/debug/records', methods=['GET'])
def debug_records():
    """Debug endpoint to view all records"""
    return jsonify({
        "records": records,
        "zones": zones
    })

if __name__ == '__main__':
    print("Starting BlueCat Mock Server...")
    print("Available endpoints:")
    print("  GET  /Services/REST/v1/login")
    print("  GET  /Services/REST/v1/logout")
    print("  GET  /Services/REST/v1/getZonesByHint")
    print("  GET  /Services/REST/v1/getHostRecordsByHint")
    print("  POST /Services/REST/v1/addHostRecord")
    print("  PUT  /Services/REST/v1/update")
    print("  DELETE /Services/REST/v1/delete")
    print("  POST /Services/REST/v1/quickDeploy")
    print("\n--- V2 Endpoints (Recommended) ---")
    print("  POST /api/v2/sessions")
    print("  DELETE /api/v2/sessions/<token>")
    print("  GET  /api/v2/zones?name={zone}")
    print("  GET  /api/v2/records?zone={id}&name={fqdn}&type={type}")
    print("  POST /api/v2/records")
    print("  PUT  /api/v2/records/<record_id>")
    print("  DELETE /api/v2/records/<record_id>")
    print("  POST /api/v2/zones/<zone_id>/deploy")
    print("\n--- Services/REST/v2 Endpoints (Aliases) ---")
    print("  POST /Services/REST/v2/sessions")
    print("  DELETE /Services/REST/v2/sessions/<token>")
    print("  GET  /Services/REST/v2/zones?name={zone}")
    print("  GET  /Services/REST/v2/records?zone={id}&name={fqdn}&type={type}")
    print("  POST /Services/REST/v2/records")
    print("  PUT  /Services/REST/v2/records/<record_id>")
    print("  DELETE /Services/REST/v2/records/<record_id>")
    print("  POST /Services/REST/v2/zones/<zone_id>/deploy")
    print("\n--- V2 Legacy BlueCat Endpoints ---")
    print("  GET  /api/v2/zones/<zone_id>/entities")
    print("  POST /api/v2/zones/<zone_id>/entities")
    print("  PUT  /api/v2/entities/<record_id>")
    print("  DELETE /api/v2/entities/<record_id>")
    print("\n--- Debug Endpoints ---")
    print("  GET  /health")
    print("  GET  /debug/records")
    print("")
    print("Use any username/password for authentication")
    print("Server running on http://localhost:5001")
    
    app.run(host='0.0.0.0', port=5001, debug=True)
