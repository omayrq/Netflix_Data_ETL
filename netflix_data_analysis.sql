
-- testing all data
select 
	* 
from 
	dbo.netflix_raw

-- checking with where showID

select 
	* 
from 
	dbo.netflix_raw
where 
	show_id = 's5023';


-- Deduplicate and Load Data
-- This step uses a CTE to remove duplicates from your netflix_raw 
-- table and fixes the "Duration" column issue where the value sometimes sits in the "Rating" column.


with cte as (
	select *, 
	ROW_NUMBER() OVER(PARTITION BY title, type ORDER BY show_id) AS rn
	from netflix_raw
)
insert into netflix 
select 
	show_id, type, title,
	CAST(date_added AS DATE),
	release_year, rating,
	CASE WHEN duration IS NULL THEN rating ELSE duration END AS duration,
	description 
From cte
WHERE rn = 1;


-- Populate Normalized Mapping Tables
-- We split the comma-separated strings (like listed_in) into individual rows.

-- Populate Genres 
insert into netflix_genre
select show_id, trim(value)
from netflix_raw
cross apply string_split(listed_in, ',')

-- Populate Directors
insert into netflix_directors
select show_id, trim(value)
from netflix_raw
cross apply string_split(director, ',')

-- initital country load (only non-nulls)

insert into netflix_country
select show_id, trim(value)
from netflix_raw
CROSS APPLY STRING_SPLIT(country, ',')
WHERE country IS NOT NULL;


--Fill Missing Countries (The "Bug" Fix)
--Now that the tables exist, we can run your logic to fill missing countries based on the director's history.

insert into netflix_country 
select nr.show_id, m.country
from netflix_raw nr
INNER JOIN (
	select nd.director, nc.country
	from netflix_country nc
	INNER JOIN netflix_directors nd ON nc.show_id = nd.show_id
	GROUP BY nd.director, nc.country
) m ON nr.director = m.director 
where nr.country IS NULL;


--Data Analysis Queries
--Now that the data is clean and split, you can run your analysis.


--Analysis 1: Directors with both Movies & TV Shows

select nd.director, 
	count(distinct case when n.type  = 'Movie' then n.show_id END) as no_of_movies,
	count(distinct case when n.type = 'TV SHOW' THEN n.show_id END) as no_of_tvshow
from netflix n 
inner join netflix_directors nd ON n.show_id = nd.show_id
group by nd.director 
having count(distinct n.type) > 1;


--Analysis 2: Country with highest Comedy Movies

SELECT TOP 1 nc.country, COUNT(DISTINCT ng.show_id) AS no_of_movies
FROM netflix_genre ng
INNER JOIN netflix_country nc ON ng.show_id = nc.show_id
INNER JOIN netflix n ON ng.show_id = n.show_id
WHERE ng.genre = 'Comedies' AND n.type = 'Movie'
GROUP BY nc.country
ORDER BY no_of_movies DESC;

--Analysis 3: Top Director per Year (Movies)

WITH cte AS (
    SELECT nd.director, YEAR(n.date_added) AS date_year, COUNT(n.show_id) AS no_of_movies
    FROM netflix n
    INNER JOIN netflix_directors nd ON n.show_id = nd.show_id
    WHERE n.type = 'Movie' AND n.date_added IS NOT NULL
    GROUP BY nd.director, YEAR(n.date_added)
),
cte2 AS (
    SELECT *, 
    ROW_NUMBER() OVER(PARTITION BY date_year ORDER BY no_of_movies DESC, director ASC) AS rn
    FROM cte
)
SELECT date_year, director, no_of_movies 
FROM cte2 
WHERE rn = 1;


--Analysis 4: Average Movie Duration per Genre

SELECT ng.genre, AVG(CAST(REPLACE(duration, ' min', '') AS INT)) AS avg_duration
FROM netflix n
INNER JOIN netflix_genre ng ON n.show_id = ng.show_id
WHERE n.type = 'Movie'
GROUP BY ng.genre;


-- Analysis 5: Directors who made both Horror and Comedy

SELECT nd.director,
    COUNT(DISTINCT CASE WHEN ng.genre = 'Comedies' THEN n.show_id END) AS no_of_comedy,
    COUNT(DISTINCT CASE WHEN ng.genre = 'Horror Movies' THEN n.show_id END) AS no_of_horror
FROM netflix n
INNER JOIN netflix_genre ng ON n.show_id = ng.show_id
INNER JOIN netflix_directors nd ON n.show_id = nd.show_id
WHERE n.type = 'Movie' AND ng.genre IN ('Comedies', 'Horror Movies')
GROUP BY nd.director
HAVING COUNT(DISTINCT ng.genre) = 2;

































