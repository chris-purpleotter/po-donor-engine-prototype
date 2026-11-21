{# D4: refunds are negative, every other gift is positive. #}
{% test pocore_refund_sign(model) %}
select *
from {{ model }}
where (is_refund and amount >= 0)
   or (not is_refund and amount <= 0)
{% endtest %}
