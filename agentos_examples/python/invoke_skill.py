#! /usr/bin/env python3

import json
import rospy
import actionlib
from agent_msgs.msg import ExecuteAction, ExecuteGoal


def feedback_callback(feedback):
  rospy.loginfo(f"Feedback progress: {feedback.progress}, state: {feedback.state}")


if __name__ == '__main__':
  rospy.init_node('invoke_skill')

  arg_skill_name = 'do_action'
  args = json.dumps({'action_id': 4}) # stand-up and ready-to-move 

  cli = actionlib.SimpleActionClient(f'/agent_skill/{arg_skill_name}/execute', ExecuteAction)

  rospy.loginfo("Waiting for action server to start...")
  if not cli.wait_for_server(timeout=rospy.Duration(3.0)):
    rospy.logerr("Action server not available after waiting.")
    exit(1)

  goal = ExecuteGoal()
  goal.invoker = 'test'
  goal.invoke_priority = 25
  goal.hold_time = 3.0
  goal.args = args

  try:
    cli.send_goal(goal, feedback_cb=feedback_callback)
  except rospy.ROSException as e:
    rospy.logerr(f"Failed to send goal: {e}")
    exit(1)

  rospy.loginfo("Waiting for result...")
  if not cli.wait_for_result(timeout=rospy.Duration(10.0)):
    rospy.logerr("Action did not finish before the timeout.")
    exit(1)

  result = cli.get_result()
  rospy.loginfo(f"Result result: {result.result}, response: {result.response}")

