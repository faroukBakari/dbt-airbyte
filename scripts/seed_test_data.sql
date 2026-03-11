-- ============================================================
-- Optional: Seed test data to simulate Airbyte Sample Data output
-- Run this CONNECTED TO airbyte_raw database
-- Mimics the Airbyte "Sample Data (Faker)" connector schema
-- IDEMPOTENT: Safe to run multiple times
-- ============================================================

-- Ensure gen_random_uuid() is available on PostgreSQL < 13
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Create mock Airbyte raw tables (matching Sample Data connector output)
CREATE TABLE IF NOT EXISTS _airbyte_raw_users (
    _airbyte_ab_id VARCHAR(36) NOT NULL DEFAULT gen_random_uuid()::varchar,
    _airbyte_data JSONB,
    _airbyte_emitted_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS _airbyte_raw_products (
    _airbyte_ab_id VARCHAR(36) NOT NULL DEFAULT gen_random_uuid()::varchar,
    _airbyte_data JSONB,
    _airbyte_emitted_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS _airbyte_raw_purchases (
    _airbyte_ab_id VARCHAR(36) NOT NULL DEFAULT gen_random_uuid()::varchar,
    _airbyte_data JSONB,
    _airbyte_emitted_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- USERS (12 users across 6 countries)
-- ============================================================
INSERT INTO _airbyte_raw_users (_airbyte_data)
SELECT * FROM (VALUES
    ('{"id": 1, "name": "Alice Johnson", "email": "alice.johnson@example.com", "gender": "Female", "title": "Ms.", "occupation": "Software Engineer", "nationality": "American", "language": "English", "academic_degree": "Master", "age": 32, "blood_type": "A+", "address": {"city": "San Francisco", "state": "California", "country_code": "US", "postal_code": "94102", "street_name": "Market St", "street_number": "123"}, "created_at": "2024-01-15T10:00:00Z", "updated_at": "2024-06-01T08:30:00Z"}'::jsonb),
    ('{"id": 2, "name": "Bob Smith", "email": "bob.smith@example.com", "gender": "Male", "title": "Mr.", "occupation": "Data Analyst", "nationality": "Canadian", "language": "English", "academic_degree": "Bachelor", "age": 28, "blood_type": "O+", "address": {"city": "Toronto", "state": "Ontario", "country_code": "CA", "postal_code": "M5V 3A8", "street_name": "King St", "street_number": "456"}, "created_at": "2024-02-20T14:30:00Z", "updated_at": "2024-05-15T12:00:00Z"}'::jsonb),
    ('{"id": 3, "name": "Charlie Brown", "email": "charlie.brown@example.com", "gender": "Male", "title": "Dr.", "occupation": "Product Manager", "nationality": "British", "language": "English", "academic_degree": "PhD", "age": 45, "blood_type": "B-", "address": {"city": "London", "state": "England", "country_code": "GB", "postal_code": "EC1A 1BB", "street_name": "Oxford St", "street_number": "789"}, "created_at": "2024-03-10T09:15:00Z", "updated_at": "2024-04-20T16:45:00Z"}'::jsonb),
    ('{"id": 4, "name": "Diana Müller", "email": "diana.mueller@example.com", "gender": "Female", "title": "Dr.", "occupation": "Data Scientist", "nationality": "German", "language": "German", "academic_degree": "PhD", "age": 38, "blood_type": "AB+", "address": {"city": "Berlin", "state": "Berlin", "country_code": "DE", "postal_code": "10115", "street_name": "Friedrichstraße", "street_number": "42"}, "created_at": "2024-01-05T08:00:00Z", "updated_at": "2024-06-10T14:00:00Z"}'::jsonb),
    ('{"id": 5, "name": "Ethan Park", "email": "ethan.park@example.com", "gender": "Male", "title": "Mr.", "occupation": "Marketing Director", "nationality": "American", "language": "English", "academic_degree": "MBA", "age": 41, "blood_type": "O-", "address": {"city": "New York", "state": "New York", "country_code": "US", "postal_code": "10001", "street_name": "5th Ave", "street_number": "800"}, "created_at": "2024-02-01T12:00:00Z", "updated_at": "2024-05-20T09:00:00Z"}'::jsonb),
    ('{"id": 6, "name": "Fatima Al-Rashid", "email": "fatima.rashid@example.com", "gender": "Female", "title": "Ms.", "occupation": "UX Designer", "nationality": "Emirati", "language": "Arabic", "academic_degree": "Master", "age": 29, "blood_type": "A-", "address": {"city": "Dubai", "state": "Dubai", "country_code": "AE", "postal_code": "00000", "street_name": "Sheikh Zayed Rd", "street_number": "1"}, "created_at": "2024-03-15T06:00:00Z", "updated_at": "2024-06-05T11:30:00Z"}'::jsonb),
    ('{"id": 7, "name": "George Tanaka", "email": "george.tanaka@example.com", "gender": "Male", "title": "Mr.", "occupation": "DevOps Engineer", "nationality": "Japanese", "language": "Japanese", "academic_degree": "Bachelor", "age": 35, "blood_type": "B+", "address": {"city": "Tokyo", "state": "Tokyo", "country_code": "JP", "postal_code": "100-0001", "street_name": "Chiyoda", "street_number": "1-1"}, "created_at": "2024-01-20T03:00:00Z", "updated_at": "2024-05-30T07:00:00Z"}'::jsonb),
    ('{"id": 8, "name": "Hannah Cohen", "email": "hannah.cohen@example.com", "gender": "Female", "title": "Ms.", "occupation": "Financial Analyst", "nationality": "American", "language": "English", "academic_degree": "Master", "age": 31, "blood_type": "O+", "address": {"city": "Chicago", "state": "Illinois", "country_code": "US", "postal_code": "60601", "street_name": "Michigan Ave", "street_number": "200"}, "created_at": "2024-02-10T15:00:00Z", "updated_at": "2024-06-15T10:00:00Z"}'::jsonb),
    ('{"id": 9, "name": "Ivan Petrov", "email": "ivan.petrov@example.com", "gender": "Male", "title": "Mr.", "occupation": "Backend Developer", "nationality": "Canadian", "language": "English", "academic_degree": "Bachelor", "age": 27, "blood_type": "A+", "address": {"city": "Vancouver", "state": "British Columbia", "country_code": "CA", "postal_code": "V6B 1A1", "street_name": "Granville St", "street_number": "300"}, "created_at": "2024-03-01T09:00:00Z", "updated_at": "2024-05-25T13:00:00Z"}'::jsonb),
    ('{"id": 10, "name": "Julia Santos", "email": "julia.santos@example.com", "gender": "Female", "title": "Ms.", "occupation": "Product Designer", "nationality": "Brazilian", "language": "Portuguese", "academic_degree": "Bachelor", "age": 26, "blood_type": "AB-", "address": {"city": "São Paulo", "state": "São Paulo", "country_code": "BR", "postal_code": "01310-100", "street_name": "Av Paulista", "street_number": "1578"}, "created_at": "2024-01-25T11:00:00Z", "updated_at": "2024-06-08T16:00:00Z"}'::jsonb),
    ('{"id": 11, "name": "Kevin O''Brien", "email": "kevin.obrien@example.com", "gender": "Male", "title": "Mr.", "occupation": "Solutions Architect", "nationality": "British", "language": "English", "academic_degree": "Master", "age": 39, "blood_type": "B-", "address": {"city": "London", "state": "England", "country_code": "GB", "postal_code": "SW1A 1AA", "street_name": "Whitehall", "street_number": "10"}, "created_at": "2024-02-15T07:30:00Z", "updated_at": "2024-06-12T09:00:00Z"}'::jsonb),
    ('{"id": 12, "name": "Lena Fischer", "email": "lena.fischer@example.com", "gender": "Female", "title": "Ms.", "occupation": "Machine Learning Engineer", "nationality": "German", "language": "German", "academic_degree": "PhD", "age": 33, "blood_type": "O+", "address": {"city": "Munich", "state": "Bavaria", "country_code": "DE", "postal_code": "80331", "street_name": "Marienplatz", "street_number": "8"}, "created_at": "2024-03-20T10:00:00Z", "updated_at": "2024-06-18T12:00:00Z"}'::jsonb)
) AS v(data)
WHERE NOT EXISTS (SELECT 1 FROM _airbyte_raw_users LIMIT 1);

-- ============================================================
-- PRODUCTS (8 vehicles across price tiers)
-- ============================================================
INSERT INTO _airbyte_raw_products (_airbyte_data)
SELECT * FROM (VALUES
    ('{"id": 101, "make": "Tesla", "model": "Model 3", "year": 2024, "price": 42990.00, "created_at": "2024-01-01T00:00:00Z"}'::jsonb),
    ('{"id": 102, "make": "Toyota", "model": "Camry", "year": 2023, "price": 28500.00, "created_at": "2024-01-01T00:00:00Z"}'::jsonb),
    ('{"id": 103, "make": "Honda", "model": "Civic", "year": 2024, "price": 25800.00, "created_at": "2024-01-01T00:00:00Z"}'::jsonb),
    ('{"id": 104, "make": "BMW", "model": "X5", "year": 2023, "price": 65900.00, "created_at": "2024-01-01T00:00:00Z"}'::jsonb),
    ('{"id": 105, "make": "Mercedes-Benz", "model": "C-Class", "year": 2024, "price": 46250.00, "created_at": "2024-01-01T00:00:00Z"}'::jsonb),
    ('{"id": 106, "make": "Ford", "model": "Mustang", "year": 2024, "price": 32515.00, "created_at": "2024-01-01T00:00:00Z"}'::jsonb),
    ('{"id": 107, "make": "Porsche", "model": "Cayenne", "year": 2023, "price": 82900.00, "created_at": "2024-01-01T00:00:00Z"}'::jsonb),
    ('{"id": 108, "make": "Hyundai", "model": "Tucson", "year": 2024, "price": 30550.00, "created_at": "2024-01-01T00:00:00Z"}'::jsonb)
) AS v(data)
WHERE NOT EXISTS (SELECT 1 FROM _airbyte_raw_products LIMIT 1);

-- ============================================================
-- PURCHASES (35 purchases — varied patterns: repeats, returns, spread)
-- ============================================================
INSERT INTO _airbyte_raw_purchases (_airbyte_data)
SELECT * FROM (VALUES
    -- Alice: 4 purchases, high spender, 0 returns
    ('{"id": 1001, "user_id": 1, "product_id": 101, "purchased_at": "2024-04-01T14:30:00Z", "added_to_cart_at": "2024-03-28T10:00:00Z", "returned_at": null}'::jsonb),
    ('{"id": 1002, "user_id": 1, "product_id": 105, "purchased_at": "2024-05-15T09:45:00Z", "added_to_cart_at": "2024-05-14T16:20:00Z", "returned_at": null}'::jsonb),
    ('{"id": 1003, "user_id": 1, "product_id": 103, "purchased_at": "2024-06-20T11:00:00Z", "added_to_cart_at": "2024-06-19T08:00:00Z", "returned_at": null}'::jsonb),
    ('{"id": 1004, "user_id": 1, "product_id": 107, "purchased_at": "2024-07-10T16:00:00Z", "added_to_cart_at": "2024-07-08T12:00:00Z", "returned_at": null}'::jsonb),

    -- Bob: 3 purchases, mid spender, 0 returns
    ('{"id": 1005, "user_id": 2, "product_id": 102, "purchased_at": "2024-05-01T11:00:00Z", "added_to_cart_at": "2024-04-30T18:30:00Z", "returned_at": null}'::jsonb),
    ('{"id": 1006, "user_id": 2, "product_id": 106, "purchased_at": "2024-06-05T14:00:00Z", "added_to_cart_at": "2024-06-04T10:00:00Z", "returned_at": null}'::jsonb),
    ('{"id": 1007, "user_id": 2, "product_id": 108, "purchased_at": "2024-07-15T09:00:00Z", "added_to_cart_at": "2024-07-14T15:00:00Z", "returned_at": null}'::jsonb),

    -- Charlie: 2 purchases, 1 return (50% return rate)
    ('{"id": 1008, "user_id": 3, "product_id": 104, "purchased_at": "2024-05-10T15:20:00Z", "added_to_cart_at": "2024-05-08T12:00:00Z", "returned_at": "2024-05-20T10:00:00Z"}'::jsonb),
    ('{"id": 1009, "user_id": 3, "product_id": 102, "purchased_at": "2024-06-25T10:00:00Z", "added_to_cart_at": "2024-06-24T08:00:00Z", "returned_at": null}'::jsonb),

    -- Diana: 5 purchases, top spender, 1 return
    ('{"id": 1010, "user_id": 4, "product_id": 107, "purchased_at": "2024-03-15T08:00:00Z", "added_to_cart_at": "2024-03-14T20:00:00Z", "returned_at": null}'::jsonb),
    ('{"id": 1011, "user_id": 4, "product_id": 101, "purchased_at": "2024-04-20T12:00:00Z", "added_to_cart_at": "2024-04-19T14:00:00Z", "returned_at": null}'::jsonb),
    ('{"id": 1012, "user_id": 4, "product_id": 105, "purchased_at": "2024-05-25T09:30:00Z", "added_to_cart_at": "2024-05-24T11:00:00Z", "returned_at": null}'::jsonb),
    ('{"id": 1013, "user_id": 4, "product_id": 104, "purchased_at": "2024-06-30T15:00:00Z", "added_to_cart_at": "2024-06-29T10:00:00Z", "returned_at": "2024-07-10T08:00:00Z"}'::jsonb),
    ('{"id": 1014, "user_id": 4, "product_id": 106, "purchased_at": "2024-07-20T11:00:00Z", "added_to_cart_at": "2024-07-19T09:00:00Z", "returned_at": null}'::jsonb),

    -- Ethan: 4 purchases, luxury buyer, 0 returns
    ('{"id": 1015, "user_id": 5, "product_id": 104, "purchased_at": "2024-04-05T10:00:00Z", "added_to_cart_at": "2024-04-03T14:00:00Z", "returned_at": null}'::jsonb),
    ('{"id": 1016, "user_id": 5, "product_id": 107, "purchased_at": "2024-05-10T13:00:00Z", "added_to_cart_at": "2024-05-09T09:00:00Z", "returned_at": null}'::jsonb),
    ('{"id": 1017, "user_id": 5, "product_id": 105, "purchased_at": "2024-06-15T16:00:00Z", "added_to_cart_at": "2024-06-14T11:00:00Z", "returned_at": null}'::jsonb),
    ('{"id": 1018, "user_id": 5, "product_id": 101, "purchased_at": "2024-07-25T08:00:00Z", "added_to_cart_at": "2024-07-24T15:00:00Z", "returned_at": null}'::jsonb),

    -- Fatima: 3 purchases, 2 returns (high return rate)
    ('{"id": 1019, "user_id": 6, "product_id": 103, "purchased_at": "2024-04-10T07:00:00Z", "added_to_cart_at": "2024-04-09T12:00:00Z", "returned_at": "2024-04-20T06:00:00Z"}'::jsonb),
    ('{"id": 1020, "user_id": 6, "product_id": 108, "purchased_at": "2024-05-20T09:00:00Z", "added_to_cart_at": "2024-05-19T14:00:00Z", "returned_at": "2024-06-01T08:00:00Z"}'::jsonb),
    ('{"id": 1021, "user_id": 6, "product_id": 106, "purchased_at": "2024-06-28T11:00:00Z", "added_to_cart_at": "2024-06-27T16:00:00Z", "returned_at": null}'::jsonb),

    -- George: 3 purchases, mid spender, 0 returns
    ('{"id": 1022, "user_id": 7, "product_id": 102, "purchased_at": "2024-03-20T04:00:00Z", "added_to_cart_at": "2024-03-19T22:00:00Z", "returned_at": null}'::jsonb),
    ('{"id": 1023, "user_id": 7, "product_id": 108, "purchased_at": "2024-05-05T06:00:00Z", "added_to_cart_at": "2024-05-04T20:00:00Z", "returned_at": null}'::jsonb),
    ('{"id": 1024, "user_id": 7, "product_id": 103, "purchased_at": "2024-06-10T03:00:00Z", "added_to_cart_at": "2024-06-09T18:00:00Z", "returned_at": null}'::jsonb),

    -- Hannah: 2 purchases, budget buyer, 0 returns
    ('{"id": 1025, "user_id": 8, "product_id": 103, "purchased_at": "2024-04-15T16:00:00Z", "added_to_cart_at": "2024-04-14T10:00:00Z", "returned_at": null}'::jsonb),
    ('{"id": 1026, "user_id": 8, "product_id": 102, "purchased_at": "2024-06-01T12:00:00Z", "added_to_cart_at": "2024-05-31T08:00:00Z", "returned_at": null}'::jsonb),

    -- Ivan: 3 purchases, 1 return
    ('{"id": 1027, "user_id": 9, "product_id": 106, "purchased_at": "2024-04-25T10:00:00Z", "added_to_cart_at": "2024-04-24T14:00:00Z", "returned_at": null}'::jsonb),
    ('{"id": 1028, "user_id": 9, "product_id": 101, "purchased_at": "2024-05-30T08:00:00Z", "added_to_cart_at": "2024-05-29T12:00:00Z", "returned_at": "2024-06-10T09:00:00Z"}'::jsonb),
    ('{"id": 1029, "user_id": 9, "product_id": 108, "purchased_at": "2024-07-05T15:00:00Z", "added_to_cart_at": "2024-07-04T11:00:00Z", "returned_at": null}'::jsonb),

    -- Julia: 2 purchases, 0 returns
    ('{"id": 1030, "user_id": 10, "product_id": 105, "purchased_at": "2024-05-12T13:00:00Z", "added_to_cart_at": "2024-05-11T09:00:00Z", "returned_at": null}'::jsonb),
    ('{"id": 1031, "user_id": 10, "product_id": 106, "purchased_at": "2024-07-01T10:00:00Z", "added_to_cart_at": "2024-06-30T15:00:00Z", "returned_at": null}'::jsonb),

    -- Kevin: 3 purchases, luxury + return pattern
    ('{"id": 1032, "user_id": 11, "product_id": 107, "purchased_at": "2024-04-08T08:00:00Z", "added_to_cart_at": "2024-04-07T12:00:00Z", "returned_at": null}'::jsonb),
    ('{"id": 1033, "user_id": 11, "product_id": 104, "purchased_at": "2024-05-18T14:00:00Z", "added_to_cart_at": "2024-05-17T10:00:00Z", "returned_at": "2024-05-28T09:00:00Z"}'::jsonb),
    ('{"id": 1034, "user_id": 11, "product_id": 101, "purchased_at": "2024-07-12T11:00:00Z", "added_to_cart_at": "2024-07-11T08:00:00Z", "returned_at": null}'::jsonb),

    -- Lena: 1 purchase, recent, 0 returns
    ('{"id": 1035, "user_id": 12, "product_id": 101, "purchased_at": "2024-07-28T09:00:00Z", "added_to_cart_at": "2024-07-27T14:00:00Z", "returned_at": null}'::jsonb)
) AS v(data)
WHERE NOT EXISTS (SELECT 1 FROM _airbyte_raw_purchases LIMIT 1);

SELECT 'Test data seeded successfully! (12 users, 8 products, 35 purchases)' AS status;
