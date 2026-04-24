#include <ros/ros.h>
#include <agent_msgs/Hold.h>
#include <agent_msgs/ReleaseHold.h>

int main(int argc, char** argv)
{
  ros::init(argc, argv, "hold_skill_test");
  ros::NodeHandle nh;

  std::string arg_skill_name = "do_action";

  // Hold skill
  std::string hold_service_name = "/agent_skill/" + arg_skill_name + "/hold";
  ros::ServiceClient hold_client = nh.serviceClient<agent_msgs::Hold>(hold_service_name);

  try
  {
    if (!ros::service::waitForService(hold_service_name, ros::Duration(5.0)))
    {
      ROS_ERROR("Service %s not available.", hold_service_name.c_str());
      return 1;
    }
  }
  catch (const ros::Exception &e)
  {
    ROS_ERROR("Service %s not available: %s", hold_service_name.c_str(), e.what());
    return 1;
  }

  ROS_INFO("Calling %s service...", hold_service_name.c_str());

  agent_msgs::Hold hold_srv;
  hold_srv.request.invoker = "test";
  hold_srv.request.invoke_priority = 25;
  hold_srv.request.hold_time = 10.0;
  hold_srv.request.preempt = 0;

  if (hold_client.call(hold_srv))
  {
    ROS_INFO("Service call was successful.");
  }
  else
  {
    ROS_ERROR("Service call failed.");
  }

  ros::Duration(3.0).sleep();

  // Release skill
  std::string release_service_name = "/agent_skill/" + arg_skill_name + "/release_hold";
  ros::ServiceClient release_client = nh.serviceClient<agent_msgs::ReleaseHold>(release_service_name);

  try
  {
    if (!ros::service::waitForService(release_service_name, ros::Duration(5.0)))
    {
      ROS_ERROR("Service %s not available.", release_service_name.c_str());
      return 1;
    }
  }
  catch (const ros::Exception &e)
  {
    ROS_ERROR("Service %s not available: %s", release_service_name.c_str(), e.what());
    return 1;
  }

  ROS_INFO("Calling %s service...", release_service_name.c_str());

  agent_msgs::ReleaseHold release_srv;
  release_srv.request.invoker = "test";

  if (release_client.call(release_srv))
  {
    ROS_INFO("Service call was successful.");
  }
  else
  {
    ROS_ERROR("Service call failed.");
  }

  return 0;
}
