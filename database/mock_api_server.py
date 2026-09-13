#!/usr/bin/env python3
import json
from http.server import BaseHTTPRequestHandler, HTTPServer

USERS = []


def json_response(handler, status, payload):
    body = json.dumps(payload).encode('utf-8')
    handler.send_response(status)
    handler.send_header('Content-Type', 'application/json')
    handler.send_header('Content-Length', str(len(body)))
    handler.end_headers()
    handler.wfile.write(body)


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/api/health':
            json_response(self, 200, {'status': 'ok'})
            return
        if self.path == '/api/rides/available':
            json_response(
                self,
                200,
                {
                    'rides': [
                        {'id': 'ride-1', 'from': 'Aeroporto', 'to': 'Bandim', 'fare': 2500, 'driver': 'Mamadou S.'},
                        {'id': 'ride-2', 'from': 'Mercado de Bandim', 'to': 'Praia', 'fare': 1800, 'driver': 'Abdulai K.'},
                    ]
                },
            )
            return
        json_response(self, 404, {'error': 'Not found'})

    def do_POST(self):
        length = int(self.headers.get('Content-Length', '0'))
        body = self.rfile.read(length)
        try:
            payload = json.loads(body.decode('utf-8')) if body else {}
        except json.JSONDecodeError:
            payload = {}

        path = self.path

        if path == '/api/auth/register':
            email = str(payload.get('email', '')).strip().lower()
            name = str(payload.get('name', '')).strip()
            password = str(payload.get('password', ''))
            role = str(payload.get('role', 'passenger'))
            if not name or not email or len(password) < 6:
                json_response(self, 400, {'error': 'Nome, e-mail e senha válidos são obrigatórios.'})
                return
            if any(user['email'] == email for user in USERS):
                json_response(self, 409, {'error': 'Este e-mail já está registrado.'})
                return

            user = {
                'id': f'user-{len(USERS) + 1}',
                'name': name,
                'email': email,
                'role': role,
                'password': password,
                'vehicle': payload.get('vehicle', ''),
                'plate': payload.get('plate', ''),
            }
            USERS.append(user)
            json_response(
                self,
                201,
                {'id': user['id'], 'name': user['name'], 'email': user['email'], 'role': user['role']},
            )
            return

        if path == '/api/auth/login':
            email = str(payload.get('email', '')).strip().lower()
            password = str(payload.get('password', ''))
            user = next((item for item in USERS if item['email'] == email and item['password'] == password), None)
            if user is None:
                json_response(self, 401, {'error': 'Credenciais inválidas.'})
                return
            json_response(
                self,
                200,
                {'id': user['id'], 'name': user['name'], 'email': user['email'], 'role': user['role']},
            )
            return

        if path == '/api/rides/request':
            destination = str(payload.get('destination', '')).strip()
            category = str(payload.get('category', 'taxi'))
            payment_method = str(payload.get('paymentMethod', 'cash'))
            if not destination:
                json_response(self, 400, {'error': 'Informe o destino da viagem.'})
                return

            fare = {'taxi': 2500, 'confort': 3500, 'moto': 1800}.get(category, 2500)
            json_response(
                self,
                200,
                {
                    'origin': 'A minha localização',
                    'destination': destination,
                    'category': category,
                    'paymentMethod': payment_method,
                    'estimatedFare': fare,
                },
            )
            return

        json_response(self, 404, {'error': 'Route not found'})

    def log_message(self, format, *args):
        return


if __name__ == '__main__':
    server = HTTPServer(('0.0.0.0', 3001), Handler)
    print('Mock API running on http://0.0.0.0:3001')
    server.serve_forever()
