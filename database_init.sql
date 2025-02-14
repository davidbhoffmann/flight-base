DELETE FROM airline_app_assignment;
DELETE FROM airline_app_booking;
DELETE FROM airport_app_runway;
DELETE FROM airport_app_airport;
DELETE FROM airline_app_flight;
DELETE FROM airline_app_passenger;
DELETE FROM airline_app_employee;
DELETE FROM airline_app_aircraft;

-- Create views
CREATE MATERIALIZED VIEW airport_and_based_crew 
AS SELECT airport_app_airport.*, 
COUNT(airline_app_employee.based_in_id) AS num_employees
FROM airport_app_airport
LEFT JOIN airline_app_employee 
ON airport_app_airport.icao_code = airline_app_employee.based_in_id
GROUP BY airport_app_airport.icao_code;

CREATE VIEW airport_stats AS
SELECT a.icao_code, 
       AVG(f.delay) AS avg_delay, 
       COUNT(DISTINCT f.number) AS num_flights, 
       SUM(COALESCE(bd.num_departing_passengers, 0) + COALESCE(ba.num_arriving_passengers, 0)) AS num_passengers 
FROM airport_app_airport a 
LEFT JOIN airline_app_flight f ON a.icao_code = f.departure_airport_id OR a.icao_code = f.destination_airport_id 
LEFT JOIN (
    SELECT flight_id, COUNT(*) AS num_departing_passengers 
    FROM airline_app_booking 
    WHERE cancelled = FALSE 
    GROUP BY flight_id
) bd ON f.number = bd.flight_id AND f.departure_airport_id = a.icao_code 
LEFT JOIN (
    SELECT flight_id, COUNT(*) AS num_arriving_passengers 
    FROM airline_app_booking 
    WHERE cancelled = FALSE 
    GROUP BY flight_id
) ba ON f.number = ba.flight_id AND f.destination_airport_id = a.icao_code 
WHERE f.cancelled = FALSE 
GROUP BY a.icao_code, a.name;

-- Stored procedure
CREATE OR REPLACE PROCEDURE cancel_flight(flight_number VARCHAR)
LANGUAGE plpgsql
AS $$
BEGIN
  -- Update bookings
  UPDATE airline_app_booking SET cancelled = true WHERE flight_id = flight_number;
  -- Remove crew assignments for the flight
  DELETE FROM airline_app_assignment WHERE flight_id = flight_number;
END;$$;

-- Trigger function to trigger and check for cancellation
CREATE OR REPLACE FUNCTION cancel_flight_trigger_function()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.cancelled THEN
    CALL cancel_flight(NEW.number);
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Corresponding trigger
CREATE OR REPLACE TRIGGER cancel_flight_trigger
AFTER UPDATE ON airline_app_flight
FOR EACH ROW
EXECUTE FUNCTION cancel_flight_trigger_function();

-- Inserting Datapoints
INSERT INTO  public.airline_app_aircraft (registration, type_series, passenger_capacity)
VALUES 
('D-ABYA',	'B748',	364),
('D-AIXP',	'A359',	293);

INSERT INTO public.airport_app_airport (icao_code, name)
VALUES 
('EDDF', 'Frankfurt Airport'),
('EDDM', 'Munich Airport'),
('KJFK', 'John F. Kennedy International Airport');

INSERT INTO public.airport_app_runway (id, length, name, airport_id) VALUES
(1, 3343, '07L', 'EDDF'),
(2, 3343, '07C', 'EDDF'),
(3, 4231, '18', 'EDDF'),
(4, 2560, '04R', 'KJFK'),
(5, 3682, '04L', 'KJFK'),
(6, 2560, '22L', 'KJFK'),
(7, 3682, '22R', 'KJFK'),
(8, 4231, '36', 'EDDF'),
(9, 3343, '25L', 'EDDF'),
(10, 3343, '25R', 'EDDF');

INSERT INTO public.airline_app_employee (id, first_name, last_name, email, role, based_in_id, spouse_id)
VALUES 
(1, 'Jürgen', 'Raps', 'raps@lufthansa.com', 'C', 'EDDF', null),
(2, 'Joong Gi', 'Joost', 'joost@lufthansa.com', 'FO', 'EDDM', null),
(3, 'Janine', 'Neumann', 'neumann@lufthansa.com', 'CC', 'EDDF', 4),
(4, 'Tobias', 'Reuter', 'treuter@lufthansa.com', 'CC', 'EDDM', 3);

INSERT INTO public.airline_app_flight (number, departure_time, arrival_time, delay, cancelled, aircraft_id, departure_airport_id, destination_airport_id)
VALUES 
('LH470', '2023-02-19 09:10:00+01', '2023-02-19 17:40:00+01', 5, 'f', 'D-AIXP', 'EDDM', 'KJFK'),
('LH480', '2023-02-20 11:12:00+01', '2023-02-20 20:10:00+01', 0, 'f', 'D-ABYA', 'EDDF', 'KJFK'),
('LH440', '2023-02-21 11:15:00+01', '2023-02-21 20:20:00+01', 80, 'f', 'D-AIXP', 'KJFK', 'EDDM');

INSERT INTO public.airline_app_assignment (id, employee_id, flight_id)
VALUES 
(1, 1, 'LH480'),
(2, 2, 'LH480'),
(3, 3, 'LH470'),
(4, 4, 'LH480'),
(5, 3, 'LH480'),
(6, 1, 'LH470'),
(7, 2, 'LH470'),
(8, 4, 'LH470'),
(9, 1, 'LH440');

INSERT INTO public.airline_app_passenger (id, first_name, last_name, status, notes)
VALUES 
(1, 'James', 'Bond', 'P', 'Likes his drinks stirred, not shaken.'),
(2, 'Rainer', 'Zufall', 'S', 'Preferes to choose his meals randomly.');

INSERT INTO public.airline_app_booking (id, "time", cancelled, flight_id, passenger_id)
VALUES 
(1, '2023-02-19 15:22:41.408284+01', 'f', 'LH470', 1),
(2, '2023-02-19 15:22:47.910238+01', 'f', 'LH480', 1),
(3, '2023-02-19 15:22:55.240668+01', 'f', 'LH440', 1),
(4, '2023-02-19 15:23:01.765973+01', 'f', 'LH470', 2),
(5, '2023-02-19 15:23:07.689948+01', 'f', 'LH480', 2),
(6, '2023-02-19 15:23:13.392197+01', 'f', 'LH440', 2);

-- Reset sequences for correct pk assignment with django after manual insert of demo data.
SELECT setval('airport_app_runway_id_seq', (SELECT MAX(id) FROM airport_app_runway)+1);
SELECT setval('airline_app_employee_id_seq', (SELECT MAX(id) FROM airline_app_employee)+1);
SELECT setval('airline_app_assignment_id_seq', (SELECT MAX(id) FROM airline_app_assignment)+1);
SELECT setval('airline_app_passenger_id_seq', (SELECT MAX(id) FROM airline_app_passenger)+1);
SELECT setval('airline_app_booking_id_seq', (SELECT MAX(id) FROM airline_app_booking)+1);