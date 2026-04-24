#include <ros/ros.h>
#include <actionlib/client/simple_action_client.h>
#include <agent_msgs/ControlAction.h>

// Feedback callback function
void feedbackCallback(const agent_msgs::ControlFeedbackConstPtr &feedback)
{
  ROS_INFO("Feedback progress: %f", feedback->progress);
}

int main(int argc, char **argv)
{
  ros::init(argc, argv, "skill_control_test");
  ros::NodeHandle nh;

  std::string arg_skill_name = "voice_interaction";
  int arg_command = 1;

  // Create the action client
  actionlib::SimpleActionClient<agent_msgs::ControlAction> ac("/agent_skill/" + arg_skill_name + "/control", true);

  ROS_INFO("Waiting for action server to start...");
  if (!ac.waitForServer(ros::Duration(3.0)))
  {
    ROS_ERROR("Action server not available after waiting.");
    return 1;
  }

  // Creating a goal
  agent_msgs::ControlGoal goal;
  goal.command = arg_command;

  // Send goal to the server with feedback callback
  try
  {
    ac.sendGoal(goal, actionlib::SimpleActionClient<agent_msgs::ControlAction>::SimpleDoneCallback(),
                actionlib::SimpleActionClient<agent_msgs::ControlAction>::SimpleActiveCallback(),
                &feedbackCallback);
  }
  catch (const ros::Exception &e)
  {
    ROS_ERROR("Failed to send goal: %s", e.what());
    return 1;
  }

  ROS_INFO("Waiting for result...");
  if (!ac.waitForResult(ros::Duration(3.0)))
  {
    ROS_ERROR("Action did not finish before the timeout.");
    return 1;
  }

  // Get and print the result
  agent_msgs::ControlResultConstPtr result = ac.getResult();
  ROS_INFO("Result: %d", result->result);

  return 0;
}
