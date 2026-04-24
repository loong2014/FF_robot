#! /usr/bin/env python3

import rospy

from agent_msgs.srv import Hold, ReleaseHold


if __name__ == '__main__':
  rospy.init_node('hold_skill_test')

  arg_skill_name = 'do_action'

  # hold skill
  hold_service_name = f'/agent_skill/{arg_skill_name}/hold'
  hold_cli = rospy.ServiceProxy(hold_service_name, Hold)

  try:
    rospy.wait_for_service(hold_service_name, timeout=5.0)
  except rospy.ROSException as e:
    rospy.logerr(f"Service {hold_service_name} not available: {e}")
    exit(1)

  rospy.loginfo(f"Calling {hold_service_name} service...")

  try:
    res = hold_cli(invoker='test', invoke_priority=25, hold_time=10.0, preempt=0)
    rospy.loginfo("Service call was successful.")
  except rospy.ServiceException as e:
    rospy.logerr(f"Service call failed: {e}")

  rospy.sleep(3.0)

  # release skill
  release_service_name = f'/agent_skill/{arg_skill_name}/release_hold'
  release_cli = rospy.ServiceProxy(release_service_name, ReleaseHold)

  try:
    rospy.wait_for_service(release_service_name, timeout=5.0)
  except rospy.ROSException as e:
    rospy.logerr(f"Service {release_service_name} not available: {e}")
    exit(1)

  rospy.loginfo(f"Calling {release_service_name} service...")

  try:
    res = release_cli(invoker='test')
    rospy.loginfo("Service call was successful.")
  except rospy.ServiceException as e:
    rospy.logerr(f"Service call failed: {e}")

