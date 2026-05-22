```sql
CREATE DATABASE company;

USE company;

CREATE TABLE emp (
    emp_id INT PRIMARY KEY,
    emp_name VARCHAR(100),
    city VARCHAR(100),
    salary DECIMAL(10,2),
    department VARCHAR(50)
) ENGINE=InnoDB;
```

```sql
INSERT INTO emp VALUES
(1,'Aarav Sharma','Hyderabad',45000,'IT'),
(2,'Vivaan Reddy','Bangalore',52000,'HR'),
(3,'Aditya Kumar','Chennai',48000,'Finance'),
(4,'Arjun Patel','Mumbai',61000,'IT'),
(5,'Sai Kiran','Pune',43000,'Admin'),
(6,'Rahul Verma','Delhi',55000,'IT'),
(7,'Karthik Rao','Hyderabad',47000,'Support'),
(8,'Rohan Gupta','Noida',62000,'IT'),
(9,'Manoj Singh','Kolkata',39000,'HR'),
(10,'Nikhil Jain','Ahmedabad',51000,'Finance'),
(11,'Suresh Babu','Vijayawada',45000,'IT'),
(12,'Praveen Kumar','Tirupati',46000,'Support'),
(13,'Harsha Vardhan','Warangal',58000,'IT'),
(14,'Vamsi Krishna','Guntur',49000,'Admin'),
(15,'Anil Reddy','Hyderabad',53000,'IT'),
(16,'Deepak Sharma','Delhi',42000,'HR'),
(17,'Lokesh Naidu','Bangalore',64000,'Finance'),
(18,'Ajay Kumar','Chennai',57000,'IT'),
(19,'Sunil Verma','Pune',41000,'Support'),
(20,'Tarun Gupta','Mumbai',60000,'IT'),
(21,'Ravi Teja','Hyderabad',52000,'Admin'),
(22,'Mohan Raj','Coimbatore',47000,'Finance'),
(23,'Kiran Kumar','Vizag',45000,'Support'),
(24,'Abhishek Singh','Lucknow',68000,'IT'),
(25,'Rajesh Patel','Surat',39000,'HR'),
(26,'Sandeep Rao','Bangalore',56000,'IT'),
(27,'Vikram Reddy','Hyderabad',61000,'Finance'),
(28,'Naresh Kumar','Delhi',43000,'Support'),
(29,'Pavan Kalyan','Vijayawada',54000,'IT'),
(30,'Ashok Sharma','Mumbai',49000,'Admin'),
(31,'Chaitanya Rao','Hyderabad',62000,'IT'),
(32,'Dinesh Kumar','Chennai',47000,'Finance'),
(33,'Ganesh Patel','Ahmedabad',45000,'Support'),
(34,'Hari Krishna','Bangalore',70000,'IT'),
(35,'Jagadeesh Reddy','Warangal',52000,'HR'),
(36,'Kishore Babu','Tirupati',41000,'Support'),
(37,'Lakshman Rao','Hyderabad',59000,'IT'),
(38,'Mahesh Verma','Delhi',46000,'Finance'),
(39,'Naveen Kumar','Pune',63000,'IT'),
(40,'Omprakash Singh','Noida',48000,'Admin'),
(41,'Prakash Reddy','Vizag',55000,'IT'),
(42,'Ramesh Gupta','Kolkata',44000,'Support'),
(43,'Srikanth Rao','Hyderabad',61000,'Finance'),
(44,'Tejas Patel','Surat',50000,'IT'),
(45,'Uday Kumar','Bangalore',67000,'IT'),
(46,'Venkatesh Naidu','Tirupati',43000,'HR'),
(47,'Yash Sharma','Mumbai',58000,'Finance'),
(48,'Zubair Khan','Hyderabad',47000,'Support'),
(49,'Bhanu Prakash','Chennai',62000,'IT'),
(50,'Charan Reddy','Vijayawada',51000,'Admin');
```

Verify:

```sql
SELECT COUNT(*) FROM emp;
```

```sql
SELECT * FROM emp LIMIT 10;
```
