#! /usr/bin/env python3

import rospy

from std_msgs.msg import Int32
from agent_msgs.msg import ExecuteStatus


def execute_callback(msg):
  rospy.loginfo(f"execute status: {msg.state}")


if __name__ == "__main__":
  rospy.init_node('skill_status')

  arg_skill_name = 'do_action'

  control_status = rospy.wait_for_message(f"/agent_skill/{arg_skill_name}/control_status", Int32, 3.0)
  rospy.loginfo(f"Skill {arg_skill_name} control status: {control_status.data}")

  subscriber = rospy.Subscriber(f"/agent_skill/{arg_skill_name}/execute_status", ExecuteStatus, execute_callback, queue_size=1)
  rospy.spin()
