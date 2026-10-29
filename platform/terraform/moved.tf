# Preserve existing addresses when enabling optional EC2 resources.
# Disabling an existing host still intentionally destroys it: review the plan.
moved {
  from = aws_key_pair.devops
  to   = aws_key_pair.devops[0]
}
moved {
  from = aws_security_group.devops
  to   = aws_security_group.devops[0]
}
moved {
  from = aws_instance.devops
  to   = aws_instance.devops[0]
}
moved {
  from = aws_eip.devops
  to   = aws_eip.devops[0]
}
moved {
  from = local_file.ansible_inventory
  to   = local_file.ansible_inventory[0]
}
moved {
  from = local_file.ansible_tf_vars
  to   = local_file.ansible_tf_vars[0]
}
