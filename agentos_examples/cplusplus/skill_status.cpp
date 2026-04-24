#include <ros/ros.h>
#include <std_msgs/Int32.h>
#include <agent_msgs/ExecuteStatus.h>

// Callback function for the execute status subscriber
void executeCallback(const agent_msgs::ExecuteStatus::ConstPtr &msg)
{
  ROS_INFO("Execute status: %d", msg->state);
}

int main(int argc, char **argv)
{
  ros::init(argc, argv, "skill_status");
  ros::NodeHandle nh;

  std::string arg_skill_name = "do_action";

  // Wait for a single message on the control_status topic
  ROS_INFO("Waiting for skill control status message...");
  std_msgs::Int32ConstPtr control_status_msg = ros::topic::waitForMessage<std_msgs::Int32>("/agent_skill/" + arg_skill_name + "/control_status", nh, ros::Duration(3.0));

  if (control_status_msg != nullptr)
  {
    ROS_INFO("Skill %s control status: %d", arg_skill_name.c_str(), control_status_msg->data);
  }
  else
  {
    ROS_ERROR("Failed to receive skill control status message within the timeout period.");
    return 1;
  }

  // Subscribe to the execute_status topic with a callback
  ros::Subscriber subscriber = nh.subscribe<agent_msgs::ExecuteStatus>("/agent_skill/" + arg_skill_name + "/execute_status", 1, executeCallback);

  // Spin to keep the subscriber active
  ros::spin();

  return 0;
}
