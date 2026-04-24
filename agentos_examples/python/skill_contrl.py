#! /usr/bin/env python3

import rospy
import actionlib

from agent_msgs.msg import ControlAction, ControlGoal


def feedback_callback(feedback):
  rospy.loginfo(f"Feedback progress: {feedback.progress}")


if __name__ == '__main__':
  rospy.init_node('skill_control_test')

  arg_skill_name = 'voice_interaction'
  arg_command = 1

  cli = actionlib.SimpleActionClient(f"/agent_skill/{arg_skill_name}/control", ControlAction)

  rospy.loginfo("Waiting for action server to start...")
  if not cli.wait_for_server(timeout=rospy.Duration(3.0)):
    rospy.logerr("Action server not available after waiting.")
    exit(1)

  goal = ControlGoal(command=arg_command)

  try:
    cli.send_goal(goal, feedback_cb=feedback_callback)
  except rospy.ROSException as e:
    rospy.logerr(f"Failed to send goal: {e}")
    exit(1)


  rospy.loginfo("Waiting for result...")
  if not cli.wait_for_result(timeout=rospy.Duration(3.0)):
    rospy.logerr("Action did not finish before the timeout.")
    exit(1)

  result = cli.get_result()
  rospy.loginfo(f"Result result: {result.result}")

